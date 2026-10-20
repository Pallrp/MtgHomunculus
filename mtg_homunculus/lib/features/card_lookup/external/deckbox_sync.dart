import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/logging/app_logger.dart';
import '../data/cards_database.dart';
import '../data/collection_database.dart';
import 'deckbox/deckbox_client.dart';
import 'deckbox/deckbox_csv.dart';
import 'deckbox/deckbox_mapping.dart';
import 'deckbox/deckbox_push.dart';
import 'deckbox/deckbox_row_edit.dart';
import 'deckbox/deckbox_row_panel.dart';
import 'external_dao.dart';
import 'session_store.dart';

/// What a pull came to.
sealed class PullOutcome {
  const PullOutcome();
}

final class Pulled extends PullOutcome {
  const Pulled(this.rows);
  final int rows;
}

/// Skipped: pulled within the cooldown, and not stale.
final class PullNotDue extends PullOutcome {
  const PullNotDue();
}

/// No session, or Deckbox turned it away. The account shows *Signed out*.
final class PullSignedOut extends PullOutcome {
  const PullSignedOut();
}

final class PullFailed extends PullOutcome {
  const PullFailed(this.message);
  final String message;
}

/// What a push did, step by step, and where it stopped if it did.
class PushReport {
  final steps = <String>[];
  int removed = 0;
  int lowered = 0;
  int added = 0;

  /// Additions Deckbox refused, or the app refused before upload.
  int refused = 0;

  /// Each refused addition, by name, and why.
  final refusals = <({String name, String reason})>[];

  /// Flagged removals, which send nothing.
  int skipped = 0;

  /// Staged changes left on the list once the push ended.
  int leftStaged = 0;

  /// Null when the push ran to the end.
  String? stoppedAt;

  /// The stage it stopped in.
  PushStage? stoppedIn;

  int get pushed => removed + lowered + added;
}

/// A push's stages, in order — the progress screen's checklist. A stage with
/// nothing to do is passed straight through.
enum PushStage {
  pull('Pull fresh counts'),
  backup('Back up the list'),
  find('Find rows'),
  remove('Remove whole rows'),
  lower('Lower counts'),
  add('Add'),
  pullAgain('Pull again');

  const PushStage(this.label);
  final String label;
}

/// One push, watched while it runs — **owned by [DeckboxSync], not by a
/// screen**, so the progress screen can be left and opened again without the
/// push noticing.
class PushRun extends ChangeNotifier {
  PushRun(this.list);

  final ExternalList list;
  final report = PushReport();

  /// The stage in progress; null before the first and once [finished].
  PushStage? stage;
  bool finished = false;

  /// How far the stage in progress is, when it is many requests — rows found,
  /// counts lowered, cards marked. Null for a stage of one request.
  ({int done, int total})? progress;

  void _enter(PushStage s) {
    stage = s;
    progress = null;
    notifyListeners();
  }

  void _progress(int done, int total) {
    progress = (done: done, total: total);
    notifyListeners();
  }

  void _step() => notifyListeners();

  void _finish() {
    report.stoppedIn = report.stoppedAt == null ? null : stage;
    stage = null;
    finished = true;
    notifyListeners();
  }
}

/// A session Deckbox turned away, mid-pull or mid-push.
class _SignedOut implements Exception {
  const _SignedOut();
}

/// Accounts, pulls and pushes — the Deckbox integration's one door to the site.
///
/// Logging in, finding lists and pulling only read (M2). [push] is **the only
/// path in the app that writes to Deckbox** (M3), and only ever on an explicit
/// push of staged changes.
///
/// **One request at a time, app-wide.** Every Deckbox call goes through
/// [_serial], so opening three lists in quick succession queues three exports
/// instead of firing them together (the plan's politeness rule).
class DeckboxSync {
  DeckboxSync._();
  static final instance = DeckboxSync._();

  static const provider = 'deckbox';

  /// How long a pull is good for before opening the list pulls again.
  static const cooldown = Duration(minutes: 5);

  ExternalDao get _dao => CollectionDatabase.instance.externalDao;

  /// Ids of the lists being pulled — queued or running — for progress bars.
  final pulling = ValueNotifier<Set<int>>(const {});

  Future<void> _tail = Future.value();
  Future<T> _serial<T>(Future<T> Function() job) {
    final run = _tail.then((_) => job());
    _tail = run.then((_) {}, onError: (_) {});
    return run;
  }

  // ---------------------------------------------------------------------------
  // Accounts
  // ---------------------------------------------------------------------------

  /// Logs in and, on success, saves the session and records the account and
  /// its lists.
  ///
  /// The lists come from the page the login lands on — Deckbox's home page,
  /// whose menu holds them (D2) — so adding an account costs no extra request.
  /// Returns the login's own result, and the account if one was saved.
  Future<({DeckboxLoginResult result, ExternalAccount? account})> login(
    String email,
    String password,
  ) =>
      _serial(() async {
        final client = DeckboxClient(onLog: AppLogger.d);
        try {
          final result = await client.login(email, password);
          final username = result.username;
          if (result.state != DeckboxSessionState.signedIn || username == null) {
            return (result: result, account: null);
          }

          final account = await _dao.upsertAccount(provider: provider, username: username);
          await SessionStore.save(
            account.id,
            DeckboxSession(username: username, cookies: client.cookies, savedAt: DateTime.now()),
          );
          try {
            await _dao.syncLists(account.id, _known(DeckboxClient.readLists(result.page.body)));
          } on DeckboxException catch (e) {
            // Signed in, but the menu did not read: the account still stands,
            // and its lists are found again on the next refresh.
            AppLogger.w('Deckbox lists not read at login: $e');
          }
          AppLogger.i('Deckbox account ${account.id} signed in as $username');
          return (result: result, account: account);
        } finally {
          client.close();
        }
      });

  /// Finds the account's lists again — the menu on Deckbox's home page.
  Future<void> refreshLists(ExternalAccount account) => _serial(() async {
        final session = await SessionStore.load(account.id);
        if (session == null) {
          await _dao.setSessionValid(account.id, false);
          return;
        }
        final client = DeckboxClient(cookies: session.cookies, onLog: AppLogger.d);
        try {
          final (lists, _) = await client.findLists();
          await _dao.syncLists(account.id, _known(lists));
          await SessionStore.save(account.id, session.withCookies(client.cookies));
        } finally {
          client.close();
        }
      });

  /// *Log out* — forgets the session on this phone. The account, its lists and
  /// its mirror stay; it shows as *Signed out* until logged in again.
  Future<void> logOut(ExternalAccount account) async {
    await SessionStore.clear(account.id);
    await _dao.setSessionValid(account.id, false);
  }

  /// *Remove from this phone* — the account, its lists and mirror, and its
  /// session. Nothing on Deckbox changes.
  Future<void> removeAccount(ExternalAccount account) async {
    await SessionStore.clear(account.id);
    await _dao.removeAccount(account.id);
  }

  /// Only the three lists the app manages; decks and anything else are skipped
  /// for now (D2).
  static List<({int remoteId, String kind, String name})> _known(List<DeckboxListRef> found) => [
        for (final l in found)
          if (l.kind != DeckboxListKind.other)
            (remoteId: l.setId, kind: l.kind.name, name: l.name),
      ];

  // ---------------------------------------------------------------------------
  // Pulls
  // ---------------------------------------------------------------------------

  /// Pulls on opening a list — unless it was pulled within [cooldown] and is
  /// not stale.
  Future<PullOutcome> pullIfDue(ExternalList list) {
    final last = list.lastPulledAt;
    final fresh = last != null &&
        DateTime.now().millisecondsSinceEpoch ~/ 1000 - last < cooldown.inSeconds;
    if (fresh && !list.stale) return Future.value(const PullNotDue());
    return pull(list);
  }

  /// Pulls one list: one export, mapped into the mirror in one transaction.
  ///
  /// Never throws. A failure is recorded on the list — and the previous mirror
  /// kept exactly as it was — so the list can say what went wrong. A list
  /// already queued is not queued twice.
  Future<PullOutcome> pull(ExternalList list) {
    final queued = _queued[list.id];
    if (queued != null) return queued;
    pulling.value = {...pulling.value, list.id};
    final run = _pull(list).whenComplete(() {
      _queued.remove(list.id);
      pulling.value = {...pulling.value}..remove(list.id);
    });
    return _queued[list.id] = run;
  }

  final _queued = <int, Future<PullOutcome>>{};

  Future<PullOutcome> _pull(ExternalList list) => _serial(() async {
        final watch = Stopwatch()..start();
        final account = await _dao.accountById(list.accountId);
        final session = account == null ? null : await SessionStore.load(account.id);
        if (account == null || session == null) {
          if (account != null) await _dao.setSessionValid(account.id, false);
          return const PullSignedOut();
        }

        final client = DeckboxClient(cookies: session.cookies, onLog: AppLogger.d);
        try {
          final fresh = await _exportIntoMirror(client, account, list);
          await SessionStore.save(account.id, session.withCookies(client.cookies));
          watch.stop();
          AppLogger.i('Deckbox pull ${list.name}: ${fresh.raw.length} rows in ${watch.elapsedMilliseconds} ms');
          return Pulled(fresh.raw.length);
        } on _SignedOut {
          return const PullSignedOut();
        } catch (e) {
          final message = _describe(e);
          AppLogger.w('Deckbox pull ${list.name} failed: $message');
          await _dao.recordPullError(list.id, message);
          return PullFailed(message);
        } finally {
          client.close();
        }
      });

  /// One export of [list], mapped and swapped into its mirror in one
  /// transaction, then the staged changes of every list showing that mirror
  /// revalidated against it. Shared by a pull and by both pulls of a push.
  /// Returns the export's raw rows, in order — what the push-time lookup
  /// locates rows by.
  ///
  /// **A Tradelist exports its Inventory** (tradelist.md, schema 4): on
  /// Deckbox they are one set of rows, and the Inventory export carries each
  /// row's count for trade. One pull serves both lists; both are marked
  /// pulled.
  Future<({List<Map<String, String>> raw, String body})> _exportIntoMirror(
    DeckboxClient client,
    ExternalAccount account,
    ExternalList list,
  ) async {
    final source = await _dao.inventoryFor(list) ?? list;
    final page = await client.exportCsv(source.remoteId, columns: 'Scryfall ID,Last Updated');
    if (!(page.contentType ?? '').contains('csv')) {
      // A signed-out export bounces to the login page, as HTML.
      final (state, _) = DeckboxClient.readSessionState(page.body);
      if (page.url.path.startsWith('/accounts/') || state == DeckboxSessionState.signedOut) {
        await _dao.setSessionValid(account.id, false);
        await _dao.recordPullError(list.id, 'Signed out');
        throw const _SignedOut();
      }
      throw DeckboxException('pull', 'the export came back as ${page.contentType}, not CSV');
    }

    final raw = DeckboxCsv.rows(page.body);
    final header = DeckboxCsv.parse(page.body).firstOrNull ?? const [];
    for (final column in const ['Count', 'Name', 'Printing Id', 'Scryfall ID']) {
      if (!header.contains(column)) {
        throw DeckboxException('pull', 'the export has no "$column" column');
      }
    }

    final rows = <DeckboxRow>[];
    for (var i = 0; i < raw.length; i++) {
      rows.add(await _resolve(DeckboxMapping.read(raw[i], i)));
    }
    final pulledAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _dao.replaceMirror(
      source.id,
      [for (final r in rows) _companion(source.id, r)],
      pulledAt: pulledAt,
    );
    await _dao.setSessionValid(account.id, true);
    for (final l in await _dao.listsSharing(source.id)) {
      if (l.id != source.id) await _dao.markPulled(l.id, pulledAt);
      final updated = await _dao.listById(l.id);
      if (updated != null) await _dao.revalidate(updated);
    }
    return (raw: raw, body: page.body);
  }

  /// Type and message only for a known failure; a raw exception's text could
  /// quote a request, so it is reduced to its type.
  /// A failure in words. **No connection** is the common one — the phone's
  /// Wi-Fi dropping mid-session (M3 device test, 2026-10-16) — and says so
  /// rather than *SocketException*. The system's own reason is logged; it
  /// names a host or an OS error, never a cookie.
  static String _describe(Object e) {
    if (e is SocketException || e is HttpException || e is HandshakeException) {
      AppLogger.w('Deckbox network: ${e.runtimeType}: '
          '${e is SocketException ? '${e.message} ${e.osError?.message ?? ''}' : e}');
      return "Couldn't reach Deckbox — check the connection. Nothing was sent";
    }
    return e is DeckboxException || e is FormatException ? '$e' : '${e.runtimeType}';
  }

  // ---------------------------------------------------------------------------
  // Push (M3)
  // ---------------------------------------------------------------------------

  /// Sends a list's staged changes to Deckbox — **the only path in the app
  /// that writes to it.**
  ///
  /// In order: a fresh pull; a backup of it; recovery of anything an earlier,
  /// interrupted push may already have sent; **removals** — every row id found
  /// first, then rows going to zero in one batch and lowered rows one request
  /// each; **additions** in one import, with refused rows taken out and the
  /// rest sent once more; a final pull; and the linked list marked stale.
  ///
  /// Removals go before additions because they write **absolute** counts
  /// worked out from the fresh pull. A flagged removal sends nothing. Whatever
  /// is not sent stays staged with its reason. Never throws: [PushReport] says
  /// how far it got.
  Future<PushReport> push(ExternalList list, {void Function(String step)? onStep}) async {
    final run = startPush(list);
    var seen = 0;
    void relay() {
      for (; seen < run.report.steps.length; seen++) {
        onStep?.call(run.report.steps[seen]);
      }
    }

    run.addListener(relay);
    await _done[run]?.future;
    run.removeListener(relay);
    return run.report;
  }

  /// Starts a push of [list] and returns it to watch — or the one already
  /// running for that list.
  PushRun startPush(ExternalList list) {
    final running = runs.value[list.id];
    if (running != null && !running.finished) return running;

    final run = PushRun(list);
    final done = Completer<void>();
    _done[run] = done;
    runs.value = {...runs.value, list.id: run};
    pushing.value = {...pushing.value, list.id};
    _serial(() => _push(run)).whenComplete(() {
      pushing.value = {...pushing.value}..remove(list.id);
      run._finish();
      _done.remove(run);
      done.complete();
    });
    return run;
  }

  /// Ids of lists being pushed.
  final pushing = ValueNotifier<Set<int>>(const {});

  /// The latest push of each list, running or finished — what the progress
  /// screen and the sheet's *Push* button watch.
  final runs = ValueNotifier<Map<int, PushRun>>(const {});
  final _done = <PushRun, Completer<void>>{};

  Future<PushReport> _push(PushRun run) async {
    final list = run.list;
    final report = run.report;
    void step(String s) {
      report.steps.add(s);
      run._step();
      AppLogger.i('Deckbox push ${list.name}: $s');
    }

    void stage(PushStage s) => run._enter(s);
    void progress(int done, int total) => run._progress(done, total);

    final account = await _dao.accountById(list.accountId);
    final session = account == null ? null : await SessionStore.load(account.id);
    if (account == null || session == null) {
      if (account != null) await _dao.setSessionValid(account.id, false);
      report.stoppedAt = 'Signed out';
      return report;
    }

    final client = DeckboxClient(cookies: session.cookies, onLog: AppLogger.d);
    // Rows are written through the list's own set id — but a Tradelist's are
    // found on its Inventory's pages, in its Inventory's export (same row ids;
    // D8 did exactly this).
    final write = DeckboxListRef(setId: list.remoteId, name: list.kind);
    final source = await _dao.inventoryFor(list) ?? list;
    final find = DeckboxListRef(setId: source.remoteId, name: source.kind);
    try {
      stage(PushStage.pull);
      final fresh = await _exportIntoMirror(client, account, list);
      step('Pulled fresh counts — ${fresh.raw.length} rows');

      stage(PushStage.backup);
      await _backup(list, fresh.body);
      step('Backed up ${list.name}');

      final recovered = await _recover(list);
      if (recovered > 0) step('$recovered changes had already landed from an earlier push');

      final staged = await _dao.stagedFor(list.id);
      await _sendRemovals(client, list, find, write, fresh.raw, staged, report, step, stage, progress);
      if (list.kind == 'tradelist') {
        await _sendMarks(client, list, find, write, fresh.raw, staged, report, step, stage, progress);
      } else {
        await _sendAdditions(client, list, staged, report, step, stage);
      }

      stage(PushStage.pullAgain);
      await _exportIntoMirror(client, account, list);
      step('Pulled again');
      await SessionStore.save(account.id, session.withCookies(client.cookies));
    } on _SignedOut {
      report.stoppedAt = 'Signed out';
    } catch (e) {
      report.stoppedAt = _describe(e);
      AppLogger.w('Deckbox push ${list.name} stopped: ${report.stoppedAt}');
    } finally {
      client.close();
      report.leftStaged = (await _dao.stagedFor(list.id)).length;
    }
    return report;
  }

  Future<void> _sendRemovals(
    DeckboxClient client,
    ExternalList list,
    DeckboxListRef find,
    DeckboxListRef write,
    List<Map<String, String>> raw,
    List<StagedChange> staged,
    PushReport report,
    void Function(String) step,
    void Function(PushStage) stage,
    void Function(int done, int total) progress,
  ) async {
    final removals = [for (final s in staged) if (s.direction == 'remove' && s.sentAt == null) s];
    report.skipped = removals.where((s) => s.flag != null).length;
    if (report.skipped > 0) step('Skipped ${report.skipped} flagged');
    final sendable = [for (final s in removals) if (s.flag == null) s];
    if (sendable.isEmpty) return;

    // Each row's place in the fresh export — what finds its page.
    final indexOf = <String, int>{};
    final twice = <String>{};
    for (var i = 0; i < raw.length; i++) {
      final id = DeckboxMapping.identityOf(raw[i]);
      if (indexOf.containsKey(id)) twice.add(id);
      indexOf.putIfAbsent(id, () => i);
    }
    final targets = <StagedChange, int>{};
    for (final s in sendable) {
      final i = indexOf[s.identityKey];
      if (i == null || twice.contains(s.identityKey)) {
        await _dao.recordStagedError(s.id, i == null ? 'No longer on Deckbox' : 'Two rows match — not sent');
        continue;
      }
      targets[s] = i;
    }
    if (targets.isEmpty) return;

    stage(PushStage.find);
    final rowIds = await client.locateRows(find, raw, targets.values, onProgress: progress);
    step('Found ${targets.length} rows');

    final countColumn = list.kind == 'tradelist' ? 'Tradelist Count' : 'Count';
    final toZero = <StagedChange>[];
    final toLower = <(StagedChange, int)>[];
    for (final MapEntry(key: s, value: i) in targets.entries) {
      final left = (int.tryParse(raw[i][countColumn] ?? '') ?? 0) - s.quantity;
      left <= 0 ? toZero.add(s) : toLower.add((s, left));
    }

    if (toZero.isNotEmpty) {
      stage(PushStage.remove);
      for (final s in toZero) {
        await _dao.markSent(s.id, 0);
      }
      _expectAccepted(await client.removeRows(write, [for (final s in toZero) rowIds[targets[s]]!]), 'remove');
      await _dao.unstage(toZero.map((s) => s.id));
      report.removed += toZero.length;
      step('Removed ${toZero.length} whole rows');
    }
    if (toLower.isNotEmpty) stage(PushStage.lower);
    var lowered = 0;
    for (final (s, left) in toLower) {
      await _dao.markSent(s.id, left);
      _expectAccepted(
        await client.updateCount(
          setId: write.setId,
          rowId: rowIds[targets[s]]!,
          count: left,
          viewingSetId: find.setId,
        ),
        'update_count',
      );
      await _dao.unstage([s.id]);
      report.lowered++;
      progress(++lowered, toLower.length);
    }
    if (toLower.isNotEmpty) step('Lowered ${toLower.length} counts');
  }

  Future<void> _sendAdditions(
    DeckboxClient client,
    ExternalList list,
    List<StagedChange> staged,
    PushReport report,
    void Function(String) step,
    void Function(PushStage) stage,
  ) async {
    final additions = [for (final s in staged) if (s.direction == 'add' && s.sentAt == null) s];
    if (additions.isEmpty) return;
    stage(PushStage.add);
    // **Never an import into a Tradelist** (tradelist.md): Deckbox replies
    // with its success script and drops every row (T2, T3), so the push would
    // unstage cards that never landed. A Tradelist's additions are marks —
    // [_sendMarks]. This guard is for a path that ever forgets.
    if (list.kind == 'tradelist') {
      throw const DeckboxException('import', 'refusing to import into a Tradelist — Deckbox drops every row');
    }

    var rows = <(StagedChange, Map<String, String>)>[];
    for (final s in additions) {
      final r = DeckboxImportFile.rowFor(_pending(s));
      if (r.refusal != null) {
        await _dao.recordStagedError(s.id, r.refusal!);
        report.refused++;
        report.refusals.add((name: s.name, reason: r.refusal!));
      } else {
        rows.add((s, r.fields!));
      }
    }
    if (rows.isEmpty) return;

    final mirror = await _dao.watchEntries(await _dao.mirrorIdOf(list)).first;
    await client.get('/'); // a page, for the anti-forgery token

    for (var attempt = 0; attempt < 2; attempt++) {
      for (final (s, _) in rows) {
        await _dao.markSent(s.id, _mirrorCount(mirror, s) + s.quantity);
      }
      final page = await client.importCsv(
        list.remoteId,
        DeckboxImportFile.write(
          [for (final (_, f) in rows) f],
          withTrade: rows.any((r) => r.$1.forTrade),
        ),
        filename: 'push.csv',
      );
      switch (ImportReply.read(page.body)) {
        case ImportAccepted():
          await _dao.unstage(rows.map((r) => r.$1.id));
          report.added += rows.length;
          step('Added ${rows.length}');
          return;
        case ImportRefused(rows: final echoed):
          final reasons = <StagedChange, String>{};
          for (final e in echoed) {
            for (final (s, _) in _sentAs(e, rows)) {
              reasons[s] = e.reason;
            }
          }
          final bad = [for (final r in rows) if (reasons.containsKey(r.$1)) r];
          if (bad.isEmpty) {
            throw const DeckboxException('import', 'refused, but no echoed row matches what was sent');
          }
          for (final (s, _) in bad) {
            await _dao.clearSent(s.id, error: reasons[s]);
            report.refusals.add((name: s.name, reason: reasons[s]!));
          }
          report.refused += bad.length;
          rows = [for (final r in rows) if (!bad.contains(r)) r];
          for (final (s, _) in rows) {
            await _dao.clearSent(s.id,
                error: attempt == 0 ? null : 'Deckbox refused the file twice — not sent');
          }
          if (rows.isEmpty || attempt == 1) {
            step('Deckbox refused ${bad.length}; nothing more sent');
            return;
          }
          step('Deckbox refused ${bad.length}; sending the other ${rows.length} again');
        case ImportUnknown():
          throw const DeckboxException('import', 'a reply this app does not recognise');
      }
    }
  }

  /// A Tradelist's additions: **marks** — owned copies put up for trade
  /// (tradelist.md, step 4). Each is one `update_count` with the Tradelist's
  /// set id, setting the row's trade count to its current count plus the
  /// mark; the row is found on the Inventory's pages, as a removal's is (D8).
  /// **Never more than the row's free copies**: the Tradelist does not add to
  /// the Inventory. Flagged marks send nothing.
  Future<void> _sendMarks(
    DeckboxClient client,
    ExternalList list,
    DeckboxListRef find,
    DeckboxListRef write,
    List<Map<String, String>> raw,
    List<StagedChange> staged,
    PushReport report,
    void Function(String) step,
    void Function(PushStage) stage,
    void Function(int done, int total) progress,
  ) async {
    final marks = [for (final s in staged) if (s.direction == 'add' && s.sentAt == null) s];
    final flagged = marks.where((s) => s.flag != null).length;
    if (flagged > 0) {
      report.skipped += flagged;
      step('Skipped $flagged flagged');
    }
    final sendable = [for (final s in marks) if (s.flag == null) s];
    if (sendable.isEmpty) return;

    final indexOf = <String, int>{};
    final twice = <String>{};
    for (var i = 0; i < raw.length; i++) {
      final id = DeckboxMapping.identityOf(raw[i]);
      if (indexOf.containsKey(id)) twice.add(id);
      indexOf.putIfAbsent(id, () => i);
    }
    // A row also staged to come off the Tradelist in this push: its count
    // moved under the mark, which would set it from a stale number.
    final removing = {for (final s in staged) if (s.direction == 'remove') s.identityKey};
    int count(int i, String column) => int.tryParse(raw[i][column] ?? '') ?? 0;

    final targets = <StagedChange, int>{};
    for (final s in sendable) {
      final i = indexOf[s.identityKey];
      final String? error;
      if (i == null) {
        error = 'No longer on Deckbox';
      } else if (twice.contains(s.identityKey)) {
        error = 'Two rows match — not sent';
      } else if (removing.contains(s.identityKey)) {
        error = 'Also staged to come off the Tradelist — not sent';
      } else if (s.quantity > count(i, 'Count') - count(i, 'Tradelist Count')) {
        error = 'Only ${count(i, 'Count') - count(i, 'Tradelist Count')} not yet for trade now — not sent';
      } else {
        error = null;
      }
      if (error != null) {
        await _dao.recordStagedError(s.id, error);
        continue;
      }
      targets[s] = i!;
    }
    if (targets.isEmpty) return;

    stage(PushStage.find);
    final rowIds = await client.locateRows(find, raw, targets.values, onProgress: progress);
    step('Found ${targets.length} rows');

    stage(PushStage.add);
    var marked = 0;
    for (final MapEntry(key: s, value: i) in targets.entries) {
      final trade = count(i, 'Tradelist Count') + s.quantity;
      await _dao.markSent(s.id, trade);
      _expectAccepted(
        await client.updateCount(
          setId: write.setId,
          rowId: rowIds[i]!,
          count: trade,
          viewingSetId: find.setId,
        ),
        'update_count',
      );
      await _dao.unstage([s.id]);
      report.added++;
      progress(++marked, targets.length);
    }
    step('Marked ${targets.length} for trade');
  }

  // ---------------------------------------------------------------------------
  // Row edits (mirror_editing.md)
  // ---------------------------------------------------------------------------

  /// Edits a mirrored row **on Deckbox, at once** — its finish, language,
  /// condition or printing — with Deckbox's own row edit (`update_single`).
  /// The second path that writes, next to [push]; not staged, as Deckbox's
  /// own panel is not.
  ///
  /// The row is found by its mirror position (one list page), its panel
  /// opened and checked against the mirror, the row saved with only [edit]'s
  /// fields changed, and the panel **opened again** to confirm — the save's
  /// reply says nothing either way (E7). Only then is the mirror changed
  /// ([ExternalDao.applyRowEdit]).
  ///
  /// Returns null when the edit landed, or why not. Never throws.
  Future<String?> editRow(ExternalList list, ExternalEntry row, RowEdit edit) async {
    if (edit.isEmpty) return null;
    final result = await _onRow<String?>(list, row, (client, rowId, panel, find) async {
      final edition = edit.edition;
      if (edition != null && !panel.editions.any((e) => e.id == edition.id)) {
        return "Deckbox doesn't list that printing for this card. Nothing was sent";
      }
      final data = DeckboxRowEdit.saveData(panel, edit);
      final after = DeckboxRowEdit.after(panel, edit);
      _expectAccepted(await client.saveRow(setId: panel.setId, data: data, viewingSetId: find.setId), 'save');

      // Confirmed on the row's panel, opened again. **Merged into a row
      // already of that variant, Deckbox may keep the other row's id** (Aegis
      // Angel and Gisela, device test 2026-10-20; E4 kept this one): the
      // panel is gone, and the edit is confirmed on that row instead — found
      // where the mirror has it, holding both counts.
      var again = _tryPanel((await client.rowPanel(rowId, viewingSetId: find.setId)).body);
      if (again == null) {
        final twin = await _dao.twinOf(row, DeckboxRowEdit.identityAfter(row.identityKey, after));
        if (twin == null) {
          AppLogger.w('Deckbox edit ${row.name}: the row is gone, and no row of the new variant to look in');
          return "Couldn't confirm the edit on Deckbox — pull to see where it stands";
        }
        final source = await _dao.listById(row.listId) ?? list;
        try {
          final twinId = await client.locateRow(
            find,
            twin.position,
            _want(twin, source, count: twin.count + row.count, tradeCount: twin.tradeCount + row.tradeCount),
          );
          again = _tryPanel((await client.rowPanel(twinId, viewingSetId: find.setId)).body);
          AppLogger.i('Deckbox edit ${row.name}: merged into row $twinId');
        } on DeckboxException catch (e) {
          AppLogger.w('Deckbox edit ${row.name}: the merged row not found — $e');
        }
      }
      final off = again == null ? 'no panel' : DeckboxRowEdit.mismatch(again, after, counts: false);
      if (off != null) {
        AppLogger.w('Deckbox edit ${row.name}: not confirmed — $off');
        return "Couldn't confirm the edit on Deckbox — pull to see where it stands";
      }
      await _dao.applyRowEdit(row, _edited(row, after, edit));
      AppLogger.i('Deckbox edit ${row.name} on ${list.name}: confirmed');
      return null;
    });
    return switch (result) {
      (value: final v, error: null) => v,
      (value: _, error: final e) => e,
    };
  }

  /// The printings Deckbox lists for a mirrored row's card — what **Change
  /// Version** may offer (an edition id from anywhere else is quietly turned
  /// into *any printing*, E7). Reads only.
  Future<({List<DeckboxEdition> editions, String? error})> editionsOf(ExternalList list, ExternalEntry row) async {
    final result = await _onRow(list, row, (_, _, panel, _) async => panel.editions);
    return (editions: result.value ?? const <DeckboxEdition>[], error: result.error);
  }

  /// Finds [row] on Deckbox, opens its panel and checks it is still the row
  /// the mirror holds — then runs [body]. A row changed on Deckbox since the
  /// last pull is not touched.
  Future<({T? value, String? error})> _onRow<T>(
    ExternalList list,
    ExternalEntry row,
    Future<T> Function(DeckboxClient client, String rowId, DeckboxRowPanel panel, DeckboxListRef find) body,
  ) =>
      _serial(() async {
        final sharing = await _dao.listsSharing(row.listId);
        if (sharing.any((l) => pushing.value.contains(l.id))) {
          return (value: null, error: 'A push is running — try again once it has finished');
        }
        for (final l in sharing) {
          if ((await _dao.stagedFor(l.id)).any((s) => s.sentAt != null && s.identityKey == row.identityKey)) {
            return (value: null, error: 'A push was cut off while sending this row — push or pull first');
          }
        }
        final account = await _dao.accountById(list.accountId);
        final session = account == null ? null : await SessionStore.load(account.id);
        if (account == null || session == null) {
          if (account != null) await _dao.setSessionValid(account.id, false);
          return (value: null, error: 'Signed out — sign in again to edit');
        }

        // The mirror's own list: a Tradelist's rows are its Inventory's.
        final source = await _dao.listById(row.listId) ?? list;
        final find = DeckboxListRef(setId: source.remoteId, name: source.kind);
        final client = DeckboxClient(cookies: session.cookies, onLog: AppLogger.d);
        try {
          final String rowId;
          try {
            rowId = await client.locateRow(find, row.position, _want(row, source));
          } on DeckboxException catch (e) {
            if (e.step != 'locate') rethrow;
            return (value: null, error: _changed);
          }
          final page = await client.rowPanel(rowId, viewingSetId: find.setId);
          if (page.url.path.startsWith('/accounts/')) {
            await _dao.setSessionValid(account.id, false);
            return (value: null, error: 'Signed out — sign in again to edit');
          }
          final panel = _tryPanel(page.body);
          if (panel == null) {
            return (value: null, error: "Deckbox's edit panel for this row didn't open — pull and try again. Nothing was sent");
          }
          final off = DeckboxRowEdit.mismatch(panel, _rawOf(row, source));
          if (off != null) {
            AppLogger.i('Deckbox row ${row.name} changed since the pull: $off');
            return (value: null, error: _changed);
          }
          final value = await body(client, rowId, panel, find);
          await SessionStore.save(account.id, session.withCookies(client.cookies));
          return (value: value, error: null);
        } catch (e) {
          final message = _describe(e);
          AppLogger.w('Deckbox row ${row.name} on ${list.name}: $message');
          return (value: null, error: message);
        } finally {
          client.close();
        }
      });

  static const _changed = 'This row changed on Deckbox since the last pull — pull first. Nothing was sent';

  /// A panel, or null for a row that is not there — Deckbox answers a gone
  /// row's panel with an empty 404.
  static DeckboxRowPanel? _tryPanel(String html) {
    try {
      return DeckboxRowPanel.parse(html);
    } on FormatException {
      return null;
    }
  }

  /// A mirror row as the list page shows it, for [DeckboxClient.locateRow] —
  /// with [count] and [tradeCount] in place of the mirror's after a merge.
  static Map<String, String> _want(ExternalEntry row, ExternalList source, {int? count, int? tradeCount}) => {
        'Name': row.name,
        'Printing Id': row.printingId,
        'Count': '${count ?? row.count}',
        if (source.kind == 'inventory') 'Tradelist Count': '${tradeCount ?? row.tradeCount}',
        'Condition': row.condition,
        'Language': row.language,
        'Foil': row.foil,
      };

  static RowRaw _rawOf(ExternalEntry row, ExternalList source) => (
        printingId: row.printingId,
        condition: row.condition,
        language: row.language,
        foil: row.foil,
        rowFlags: row.rowFlags,
        count: row.count,
        tradeCount: source.kind == 'inventory' ? row.tradeCount : null,
      );

  /// The mirror row's new fields once [edit] is confirmed: the raw ones as
  /// the export will show them, and the app's mapping of them.
  static ExternalEntriesCompanion _edited(ExternalEntry row, RowRaw after, RowEdit edit) {
    final edition = edit.edition;
    final any = edition == null ? row.anyPrinting : edition.id == 0;
    final code = edition == null ? row.editionCode : edition.code.toLowerCase();
    return ExternalEntriesCompanion(
      printingId: Value(after.printingId),
      condition: Value(after.condition),
      language: Value(after.language),
      foil: Value(after.foil),
      identityKey: Value(DeckboxRowEdit.identityAfter(row.identityKey, after)),
      edition: edition == null ? const Value.absent() : Value(edition.name),
      editionCode: Value(code),
      cardNumber: edition == null ? const Value.absent() : Value(edition.number),
      // A note was about the old printing.
      printingNote: edition == null ? const Value.absent() : const Value(''),
      anyPrinting: Value(any),
      // A printing matched to none of the app's stays unmapped until a pull;
      // the card's art is kept either way.
      cardId: edition == null ? const Value.absent() : Value(any ? null : edit.cardId),
      cardRef: edition == null ? const Value.absent() : Value(edit.cardId ?? row.cardRef ?? row.cardId),
      finish: Value(code.endsWith('_e')
          ? DeckboxMapping.etched
          : after.foil == 'foil'
              ? DeckboxMapping.foil
              : any
                  ? null
                  : DeckboxMapping.nonfoil),
      languageCode: Value(DeckboxMapping.languages[after.language]),
      conditionCode: Value(DeckboxMapping.conditions[after.condition]),
      lastUpdated: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
    );
  }

  /// Before sending anything: staged rows an interrupted push already sent are
  /// checked against the fresh pull. Landed — unstaged; not landed — sent
  /// again as normal. Returns how many had landed.
  Future<int> _recover(ExternalList list) async {
    final sent = [for (final s in await _dao.stagedFor(list.id)) if (s.sentAt != null) s];
    if (sent.isEmpty) return 0;
    final mirror = await _dao.watchEntries(await _dao.mirrorIdOf(list)).first;
    var landed = 0;
    for (final s in sent) {
      final expected = s.expectedCount ?? -1;
      final bool done;
      if (s.direction == 'remove') {
        final row = mirror.where((e) => e.identityKey == s.identityKey).firstOrNull;
        done = row == null ? expected == 0 : ExternalDao.countOn(list, row) == expected;
      } else if (list.kind == 'tradelist') {
        // A mark: its row's count for trade reached what was sent.
        final row = mirror.where((e) => e.identityKey == s.identityKey).firstOrNull;
        done = row != null && row.tradeCount >= expected;
      } else {
        done = _mirrorCount(mirror, s) >= expected;
      }
      if (done) {
        await _dao.unstage([s.id]);
        landed++;
      } else {
        await _dao.clearSent(s.id);
      }
    }
    return landed;
  }

  /// Copies of what an addition adds, already on the list — its printing (or,
  /// generic, its card) in its variant. An attribute a generic addition leaves
  /// unset matches whatever Deckbox filled in.
  static int _mirrorCount(List<ExternalEntry> mirror, StagedChange s) => mirror
      .where((e) =>
          (s.anyPrinting ? e.anyPrinting && e.name == s.name : e.cardId == s.cardId) &&
          (s.finish == null || e.finish == s.finish) &&
          (s.languageCode == null || e.languageCode == s.languageCode) &&
          (s.conditionCode == null || e.conditionCode == s.conditionCode))
      .fold(0, (n, e) => n + e.count);

  /// The sent rows an echoed refusal stands for: those matching every column
  /// it echoed — or, failing that, the one sent row with its name. Deckbox may
  /// echo a cell the file left blank filled in.
  static List<(StagedChange, Map<String, String>)> _sentAs(
    EchoedRow e,
    List<(StagedChange, Map<String, String>)> sent,
  ) {
    final exact = [for (final r in sent) if (DeckboxImportFile.echoKey(r.$2) == e.echoKey) r];
    if (exact.isNotEmpty) return exact;
    final named = [for (final r in sent) if (r.$2['Name'] == e.values['Name']) r];
    return named.length == 1 ? named : const [];
  }

  static PendingAddition _pending(StagedChange s) => (
        id: s.id,
        name: s.name,
        cardId: s.cardId,
        anyPrinting: s.anyPrinting,
        finish: s.finish,
        languageCode: s.languageCode,
        conditionCode: s.conditionCode,
        setCode: s.setCode,
        setName: s.setName,
        collectorNumber: s.collectorNumber,
        quantity: s.quantity,
        forTrade: s.forTrade,
      );

  /// A write's reply: anything but a 200, or the bounce to the login page the
  /// decks-only batch gave on a detailed set (D5), is a refusal.
  static void _expectAccepted(DeckboxPage page, String what) {
    if (page.status != 200 || page.body.contains("window.location.href = '/accounts/login'")) {
      throw DeckboxException(what, 'Deckbox refused it (${page.status})');
    }
  }

  /// **Minimal pre-push backup** (M4 polishes it): the fresh export, as
  /// Deckbox wrote it, in the app's files. The last five per list are kept.
  Future<void> _backup(ExternalList list, String csv) async {
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/deckbox_backups');
    await dir.create(recursive: true);
    final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    await File('${dir.path}/list${list.id}_$stamp.csv').writeAsString(csv);
    final mine = (await dir.list().toList())
        .whereType<File>()
        .where((f) => f.uri.pathSegments.last.startsWith('list${list.id}_'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final old in mine.take(mine.length - 5 < 0 ? 0 : mine.length - 5)) {
      await old.delete();
    }
  }

  /// An etched row exports no Scryfall id; its printing is found in the card
  /// cache by the base set and number (`mh2_e` #389 → `mh2` 389). Not found —
  /// or no card cache yet — leaves it unmapped, which the mirror shows.
  Future<DeckboxRow> _resolve(DeckboxRow row) async {
    final lookup = row.etchedLookup;
    if (lookup == null || row.cardId != null) return row;
    final card = await CardsDatabase.instance.cardBySetNumber(lookup.set, lookup.number);
    return card == null ? row : row.withCard(card.id);
  }

  static ExternalEntriesCompanion _companion(int listId, DeckboxRow r) =>
      ExternalEntriesCompanion.insert(
        listId: listId,
        position: r.position,
        count: r.count,
        tradeCount: Value(r.tradeCount),
        printingId: r.printingId,
        condition: r.condition,
        language: r.language,
        foil: r.foil,
        rowFlags: r.rowFlags,
        identityKey: r.identityKey,
        name: r.name,
        edition: r.edition,
        editionCode: r.editionCode,
        cardNumber: r.cardNumber,
        printingNote: r.printingNote,
        lastUpdated: Value(r.lastUpdated),
        anyPrinting: r.anyPrinting,
        cardId: Value(r.cardId),
        cardRef: Value(r.cardRef),
        finish: Value(r.finish),
        languageCode: Value(r.languageCode),
        conditionCode: Value(r.conditionCode),
      );
}
