import 'dart:async';

import 'package:flutter/material.dart' hide Card;

import '../data/cards_database.dart';
import '../data/collection_database.dart';
import '../external/copy_match.dart';
import '../external/deckbox_sheet_model.dart' show ScanTarget;
import '../external/external_dao.dart';
import '../models/scan_defaults.dart';
import '../widgets/destination_picker.dart';
import 'deckbox_list_screen.dart';
import 'listing_detail_screen.dart';
import 'printing_checklist_screen.dart';
import 'remove_match_screen.dart';

/// *Cut to* and *Copy to*, from any list to any list (M3 step 4; plan, *Cut /
/// Copy*): the destination picker, then whatever that destination needs.
///
/// | Destination                 | What happens                                     |
/// | --------------------------- | ------------------------------------------------ |
/// | An app list                 | Added; generic cards get a printing first, on [PrintingChecklistScreen] |
/// | A Deckbox list → **Add**    | Staged to add, and the list opens               |
/// | A Deckbox list → **Remove** | Matched to its rows — [RemoveMatchScreen] when not every card matched on its own — staged to remove, and the list opens |
/// | This list's other section   | To remove → To add as is; To add → To remove matched as above |
///
/// **Cut moves only what landed**: a card skipped, or the part of it Deckbox
/// does not have, stays where it was. The mirror is never cut — it is
/// Deckbox's; staging its removal is.
///
/// **Then the destination opens, in place of the source** (decided
/// 2026-10-17) — the move is done, and the list it went to is the one to look
/// at. Replacing rather than stacking also keeps one scanner, and one camera,
/// alive at a time. A move between a list's own sections stays put.
///
/// Each batch is **one transaction**: a 2,000-card copy wakes the screens
/// watching the lists once, not 2,000 times.
///
/// Returns whether anything moved, so the caller can leave selection.
class MoveCardsFlow {
  MoveCardsFlow._(this.context, this.lines, this.cut, this.sourceName, this.fromAppList, this.fromDeckbox);

  final BuildContext context;
  final List<CardLine> lines;
  final bool cut;

  /// The source's name, for *stays in Trade binder*.
  final String sourceName;
  final int? fromAppList;
  final ExternalList? fromDeckbox;

  CollectionDatabase get _db => CollectionDatabase.instance;
  ExternalDao get _dao => _db.externalDao;
  CardsDatabase get _cards => CardsDatabase.instance;

  /// Copies landed per line, for *Cut*.
  final _landed = <int, int>{};

  /// The app list's own `cutTo` moved them: nothing is left to take out.
  bool _movedByList = false;
  final _skipped = <String>[];

  static Future<bool> run(
    BuildContext context, {
    required List<CardLine> lines,
    required bool cut,
    required String sourceName,
    int? fromAppList,
    ExternalList? fromDeckbox,
    List<ScanTarget> thisList = const [],
  }) async {
    if (lines.isEmpty) return false;
    final n = lines.length;
    final dest = await pickDestination(
      context,
      title: '${cut ? 'Cut' : 'Copy'} $n ${n == 1 ? 'card' : 'cards'} to',
      thisList: cut ? thisList : const [],
      excludeAppList: fromAppList,
      excludeDeckboxList: fromDeckbox?.id,
    );
    if (dest == null || !context.mounted) return false;
    // Into this list's other section, only rows from the opposite one move:
    // a selection spanning both leaves what is already there in place.
    final moving = dest is ToSection
        ? [
            for (final l in lines)
              if (l.source case FromStaged(
                :final direction,
              ) when direction == (dest.section == ScanTarget.add ? 'remove' : 'add'))
                l,
          ]
        : lines;
    if (moving.isEmpty) return false;
    return MoveCardsFlow._(context, moving, cut, sourceName, fromAppList, fromDeckbox)._to(dest);
  }

  Future<bool> _to(Destination dest) async {
    Widget? open;
    switch (dest) {
      case ToAppList(:final list):
        if (!await _intoAppList(list)) return false;
        _report('${cut ? 'Moved' : 'Copied'} ${_count()} to ${list.name}');
        open = ListingDetailScreen(listId: list.id);
      case ToSection(:final section):
        final list = fromDeckbox!;
        if (section == ScanTarget.add) {
          // A Tradelist's To add marks Inventory rows; anywhere else, adds.
          if (list.kind == 'tradelist') {
            if (!await _stageMarks(list)) return false;
          } else {
            await _stageAdditions(list);
          }
        } else if (!await _stageRemovals(list)) {
          return false;
        }
        _report('Moved ${_count()} to ${section.label}');
      case ToDeckbox(:final list, :final account):
        final add = await pickDirection(context, cards: lines.length, list: list, account: account);
        if (add == null || !context.mounted) return false;
        if (add && list.kind == 'tradelist') {
          if (!await _stageMarks(list, accountName: account.username)) return false;
        } else if (add) {
          await _stageAdditions(list);
        } else if (!await _stageRemovals(list, accountName: account.username)) {
          return false;
        }
        _report('Staged ${_count()} ${add ? 'to add to' : 'to remove from'} ${list.name}');
        open = DeckboxListScreen(listId: list.id);
    }
    // Settled before the source screen goes: Cut takes out what landed.
    if (cut) await _takeOutLanded();
    if (open != null && _landed.isNotEmpty && context.mounted) {
      unawaited(Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => open!)));
    }
    return _landed.isNotEmpty;
  }

  int _count() => _landed.values.fold(0, (n, q) => n + q);

  void _report(String done) {
    if (!context.mounted) return;
    final n = _skipped.length;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          // A few names, then a count: a whole Inventory copied can skip
        // thousands, and a snackbar is no place to list them.
        content: Text(n == 0
            ? done
            : '$done · $n skipped: ${_skipped.take(3).join(', ')}${n > 3 ? ' and ${n - 3} more' : ''}'),
          duration: Duration(seconds: n == 0 ? 2 : 4),
        ),
      );
  }

  // ---------------------------------------------------------------------------
  // Into an app list
  // ---------------------------------------------------------------------------

  /// False when the user backed out of the printing checklist.
  Future<bool> _intoAppList(CardList target) async {
    // App list to app list: the list's own move, which keeps everything.
    if (fromAppList != null && lines.every((l) => l.source is FromAppEntry)) {
      final ids = [for (final l in lines) l.source.id];
      await (cut ? _db.cutTo(ids, target.id) : _db.copyTo(ids, target.id));
      _movedByList = true;
      for (var i = 0; i < lines.length; i++) {
        _landed[i] = lines[i].quantity;
      }
      return true;
    }

    // An app list holds printings: every generic card is given one first —
    // all of them on one checklist, before anything is added.
    final generic = [
      for (var i = 0; i < lines.length; i++)
        if (lines[i].anyPrinting) i,
    ];
    var printingOf = <int, Card?>{};
    if (generic.isNotEmpty) {
      if (!context.mounted) return false;
      final answered = await Navigator.of(context).push<Map<int, Card?>>(
        MaterialPageRoute(
          builder: (_) => PrintingChecklistScreen(
            lines: lines,
            generic: generic,
            targetName: target.name,
            sourceName: sourceName,
            cut: cut,
          ),
        ),
      );
      if (answered == null) return false;
      printingOf = answered;
    }

    final d = ScanDefaults.current;
    await _db.transaction(() async {
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.unmapped) {
          _skipped.add('${line.name} (no printing)');
          continue;
        }
        final Card? card;
        if (line.anyPrinting) {
          card = printingOf[i];
          if (card == null) {
            _skipped.add(line.name);
            continue;
          }
        } else {
          card = await _cards.cardById(line.cardId!);
        }
        await _addToAppList(target, line, card, d);
        _landed[i] = line.quantity;
      }
    });
    return true;
  }

  Future<void> _addToAppList(CardList target, CardLine line, Card? card, ScanDefaults d) async {
    final set = card == null
        ? null
        : await (_cards.select(_cards.sets)..where((s) => s.code.equals(card.setCode))).getSingleOrNull();
    await _db.addCard(
      listId: target.id,
      cardId: card?.id ?? line.cardId!,
      name: line.name,
      setCode: card?.setCode ?? line.setCode,
      setName: set?.name ?? line.setName,
      collectorNumber: card?.collectorNumber ?? line.collectorNumber,
      finish: line.finish ?? d.finishFor(card?.finishes ?? 1),
      language: line.languageCode ?? d.language,
      condition: line.conditionCode ?? d.condition,
      quantity: line.quantity,
    );
  }

  // ---------------------------------------------------------------------------
  // Into a Deckbox list
  // ---------------------------------------------------------------------------

  /// To add — every card as it is. *Any printing* only goes to a Wishlist:
  /// nothing in the app creates a generic row anywhere else.
  Future<void> _stageAdditions(ExternalList list) => _dao.transaction(() async {
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.unmapped) {
        _skipped.add('${line.name} (no printing)');
        continue;
      }
      if (line.anyPrinting && list.kind != 'wishlist') {
        _skipped.add('${line.name} (any printing)');
        continue;
      }
      await _dao.stageAddition(
        listId: list.id,
        name: line.name,
        cardId: line.cardId,
        cardRef: line.cardRef,
        anyPrinting: line.anyPrinting,
        finish: line.finish,
        languageCode: line.languageCode,
        conditionCode: line.conditionCode,
        setCode: line.setCode,
        setName: line.setName,
        collectorNumber: line.collectorNumber,
        quantity: line.quantity,
      );
      _landed[i] = line.quantity;
    }
  });

  /// A Tradelist's To add — **marks**: each card matched to an Inventory row
  /// with free copies, and staged to mark that many for trade (tradelist.md,
  /// step 4). This is *Copy to → Tradelist* from the Inventory — "stage every
  /// card for trade": what is already all for trade is **skipped quietly**,
  /// counted in the result, never a stop. Only a card that could be several
  /// rows asks, on [RemoveMatchScreen]. False when the user backed out.
  Future<bool> _stageMarks(ExternalList list, {String? accountName}) async {
    final rows = [
      for (final e in await _dao.watchEntries(await _dao.mirrorIdOf(list)).first)
        if (ExternalDao.freeOf(e) > 0) e,
    ];
    final staged = await _dao.stagedFor(list.id);
    int left(ExternalEntry e) =>
        ExternalDao.freeOf(e) -
        staged
            .where((s) => s.direction == 'add' && s.identityKey == e.identityKey)
            .fold(0, (n, s) => n + s.quantity);

    var matches = CopyMatcher.matchAll(lines: lines, rows: rows, left: left, words: CopyMatcher.markWords);
    if (matches.any((m) => m is Choose)) {
      if (!context.mounted) return false;
      final answered = await Navigator.of(context).push<List<LineMatch>>(MaterialPageRoute(
        builder: (_) => RemoveMatchScreen(
          lines: lines,
          rows: rows,
          list: list,
          left: left,
          accountName: accountName ?? '',
          sourceName: sourceName,
          title: 'Mark for trade on ${list.name}',
          words: CopyMatcher.markWords,
          excess: (n) => '$n already for trade',
        ),
      ));
      if (answered == null) return false;
      matches = answered;
    }

    await _dao.transaction(() async {
      for (var i = 0; i < matches.length; i++) {
        final m = matches[i];
        if (m is Placed) {
          final took = await _dao.stageMark(list: list, row: m.row, quantity: m.quantity);
          if (took > 0) _landed[i] = took;
        } else if (m is Unplaced) {
          _skipped.add(m.line.name);
        }
      }
    });
    return true;
  }

  /// To remove — matched to the list's rows. Every card matched on its own
  /// stages with no stop; otherwise [RemoveMatchScreen] asks first. False when
  /// the user backed out.
  Future<bool> _stageRemovals(ExternalList list, {String? accountName}) async {
    final rows = [
      for (final e in await _dao.watchEntries(await _dao.mirrorIdOf(list)).first)
        if (ExternalDao.countOn(list, e) > 0) e,
    ];
    final staged = await _dao.stagedFor(list.id);
    int left(ExternalEntry e) =>
        ExternalDao.countOn(list, e) -
        staged
            .where((s) => s.direction == 'remove' && s.identityKey == e.identityKey)
            .fold(0, (n, s) => n + s.quantity);

    var matches = CopyMatcher.matchAll(lines: lines, rows: rows, left: left);
    final clean = matches.every((m) => m is Placed && m.excess == 0);
    if (!clean) {
      if (!context.mounted) return false;
      final answered = await Navigator.of(context).push<List<LineMatch>>(
        MaterialPageRoute(
          builder: (_) => RemoveMatchScreen(
            lines: lines,
            rows: rows,
            list: list,
            left: left,
            accountName: accountName ?? '',
            sourceName: sourceName,
          ),
        ),
      );
      if (answered == null) return false;
      matches = answered;
    }

    await _dao.transaction(() async {
      for (var i = 0; i < matches.length; i++) {
        final m = matches[i];
        if (m is Placed) {
          final took = await _dao.stageRemoval(list: list, row: m.row, quantity: m.quantity);
          if (took > 0) _landed[i] = took;
        }
      }
    });
    return true;
  }

  // ---------------------------------------------------------------------------

  /// *Cut*: what landed leaves its source; the rest stays.
  Future<void> _takeOutLanded() async {
    if (_movedByList) return;
    await _db.transaction(() async {
      for (final MapEntry(key: i, value: n) in _landed.entries) {
        switch (lines[i].source) {
          case FromAppEntry(:final id):
            final e = await _db.entryById(id);
            if (e != null) await _db.setQuantity(id, e.quantity - n);
          case FromStaged(:final id):
            final s = await _dao.stagedById(id);
            if (s != null) await _dao.setStagedQuantity(id, s.quantity - n);
          case FromMirror():
            break;
        }
      }
    });
  }
}
