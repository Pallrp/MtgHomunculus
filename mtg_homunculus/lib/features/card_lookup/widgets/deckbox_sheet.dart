import 'package:flutter/material.dart';

import '../data/collection_database.dart';
import '../external/deckbox_sheet_model.dart';

export '../external/deckbox_sheet_model.dart' show ScanTarget;
import '../external/copy_match.dart' show CardLine;
import '../external/deckbox_sync.dart';
import '../external/external_dao.dart';
import '../models/deckbox_prefs.dart';
import '../theme/picker_tokens.dart';
import 'any_printing_chip.dart';
import 'deckbox_rows.dart';
import '../screens/move_cards_flow.dart';
import 'deckbox_section.dart';
import 'sheet_parts.dart';

enum _Section { add, remove, deckbox }

/// How *On Deckbox* is ordered. The staged sections stay newest first.
enum DeckboxSort {
  deckbox('Name (Deckbox order)'),
  set('Set');

  const DeckboxSort(this.label);
  final String label;

  List<ExternalEntry> apply(List<ExternalEntry> rows) => switch (this) {
        DeckboxSort.deckbox => rows,
        DeckboxSort.set => [...rows]..sort((a, b) {
            final s = a.editionCode.compareTo(b.editionCode);
            if (s != 0) return s;
            final n = (int.tryParse(a.cardNumber) ?? 1 << 30).compareTo(int.tryParse(b.cardNumber) ?? 1 << 30);
            return n != 0 ? n : a.cardNumber.compareTo(b.cardNumber);
          }),
      };
}

/// A Deckbox list's sheet (M3) — the listing sheet's shape, peek and full,
/// over the camera, with the list's three sections:
///
/// ```
/// To add       ◉  staged additions        x2 / +2
/// To remove    ○  staged removals         −2 of 3
/// On Deckbox      the mirror              3×  (−1 / +1 beside it)
/// ```
///
/// **Peek** says where a scan goes — *Scanning to To add · Inventory* — over
/// the target section's newest row, or the card just scanned.
///
/// Every change here is **staged**, never sent: only *Push* writes to Deckbox.
class DeckboxSheet extends StatefulWidget {
  const DeckboxSheet({
    super.key,
    required this.list,
    required this.account,
    required this.mirror,
    required this.staged,
    required this.scrollController,
    required this.sheetController,
    required this.minSheetSize,
    required this.maxSheetSize,
    required this.cameraActive,
    required this.target,
    required this.onTargetChanged,
    required this.onCollapse,
    required this.onManualAdd,
    required this.onPush,
    required this.onPull,
    required this.onOpenStaged,
    required this.onOpenMirror,
    this.anyPrinting,
    this.lastStagedId,
    this.pulseStagedId,
  });

  final ExternalList list;
  final ExternalAccount? account;
  final List<ExternalEntry> mirror;
  final List<StagedChange> staged;

  final ScrollController scrollController;
  final DraggableScrollableController sheetController;
  final double minSheetSize;
  final double maxSheetSize;
  final bool cameraActive;

  final ScanTarget target;
  final void Function(ScanTarget) onTargetChanged;

  final VoidCallback onCollapse;
  final VoidCallback onManualAdd;
  final VoidCallback onPush;
  final VoidCallback onPull;

  /// A staged addition tapped: its detail, for chips and version.
  final void Function(StagedChange) onOpenStaged;

  /// A mirrored row tapped: its detail — its − / +, and its edit on Deckbox
  /// (mirror_editing.md).
  final void Function(ExternalEntry) onOpenMirror;

  /// A Wishlist's *Any printing* setting — the chip in the peek. Null on
  /// other lists.
  final ValueNotifier<bool>? anyPrinting;

  /// The row a scan or Manual Add just staged — what the peek shows.
  final int? lastStagedId;

  /// A frame was discarded because this staged row's card was just scanned.
  final int? pulseStagedId;

  static const double _chevHalf = PickerTokens.chevron / 2;

  /// The peek's *Scanning to …* line — taller on a Wishlist, where it holds
  /// the 44 dp *Any printing* chip.
  static const double _peekLabel = 22;
  static const double _peekLabelWithChip = 52;

  /// As [ListingSheet.peekContent], plus the target line.
  static double peekContentFor({required bool wishlist}) =>
      _chevHalf * 3 + PickerTokens.thumbHeight + (wishlist ? _peekLabelWithChip : _peekLabel);

  @override
  State<DeckboxSheet> createState() => _DeckboxSheetState();
}

class _DeckboxSheetState extends State<DeckboxSheet> {
  final _folded = <_Section>{};
  bool _searching = false;
  String _query = '';
  DeckboxSort _sort = DeckboxSort.deckbox;

  /// The one staged row showing its stepper: `s<id>`. (A mirrored row,
  /// `m<id>`, opens its detail instead.)
  String? _expanded;

  /// Multi-select (M3 step 4), keyed as [_expanded] is. Opens with nothing
  /// picked — unlike an app list, *everything* here includes the whole mirror.
  bool _selecting = false;
  final _picked = <String>{};

  @override
  void didUpdateWidget(DeckboxSheet old) {
    super.didUpdateWidget(old);
    // Back to the camera ends selecting: the peek has no checkboxes.
    if (widget.cameraActive && !old.cameraActive && _selecting) {
      _selecting = false;
      _picked.clear();
    }
  }

  void _togglePick(String key) =>
      setState(() => _picked.contains(key) ? _picked.remove(key) : _picked.add(key));

  /// A section's select-all: every key in it picked, none, or some (null).
  ({bool? state, VoidCallback onTap})? _sectionCheck(List<String> keys) {
    if (!_selecting) return null;
    final n = keys.where(_picked.contains).length;
    return (
      state: n == 0 ? false : (n == keys.length ? true : null),
      onTap: () => setState(() => n == keys.length ? _picked.removeAll(keys) : _picked.addAll(keys)),
    );
  }

  ExternalDao get _dao => CollectionDatabase.instance.externalDao;

  bool get _full => !widget.cameraActive;
  bool get _tradelist => widget.list.kind == 'tradelist';

  void _toggle() => widget.sheetController.animateTo(
        widget.cameraActive ? widget.maxSheetSize : widget.minSheetSize,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );

  void _fold(_Section s) => setState(() => _folded.contains(s) ? _folded.remove(s) : _folded.add(s));

  void _expand(String key) => setState(() => _expanded = _expanded == key ? null : key);

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  // ---------------------------------------------------------------------------
  // Staging from the rows
  // ---------------------------------------------------------------------------

  Future<void> _stageRemoval(ExternalEntry row, {int quantity = 1}) async {
    final took = await _dao.stageRemoval(list: widget.list, row: row, quantity: quantity);
    if (took == 0 && mounted) _toast('All of ${row.name} is already staged to remove');
  }

  Future<void> _stageWholeRow(ExternalEntry row) =>
      _stageRemoval(row, quantity: ExternalDao.countOn(widget.list, row));


  Future<void> _setQuantity(StagedChange s, int q) async {
    await _dao.setStagedQuantity(s.id, q);
  }

  Future<void> _unstage(StagedChange s) => _dao.unstage([s.id]);

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    final navBar = MediaQuery.viewPaddingOf(context).bottom;
    final model = DeckboxSheetModel(
      list: widget.list,
      mirror: widget.mirror,
      staged: widget.staged,
      query: _full && _searching ? _query : '',
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: DeckboxSheet._chevHalf,
          left: 0,
          right: 0,
          bottom: 0,
          child: Material(
            color: t.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            clipBehavior: Clip.antiAlias,
            child: CustomScrollView(
              controller: widget.scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: _full
                  ? [
                      SliverToBoxAdapter(child: _mgmtBar(context, model)),
                      SliverToBoxAdapter(child: _slot(context)),
                      SliverToBoxAdapter(child: _statusRow(context, model)),
                      ..._sections(context, model),
                      SliverToBoxAdapter(child: SizedBox(height: navBar + 8)),
                    ]
                  : [
                      SliverToBoxAdapter(child: _peek(context, model)),
                      SliverToBoxAdapter(child: SizedBox(height: navBar)),
                    ],
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Center(child: SheetChevron(open: _full, onTap: _toggle)),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Peek
  // ---------------------------------------------------------------------------

  Widget _peek(BuildContext context, DeckboxSheetModel model) {
    final t = PickerTokens.of(context);
    final adding = widget.target == ScanTarget.add;
    final rows = adding
        ? [for (final a in model.additions) a.staged]
        : [for (final r in model.removals) r.staged];
    final shown = rows.where((s) => s.id == widget.lastStagedId).firstOrNull ?? rows.firstOrNull;
    final chip = widget.anyPrinting;

    return Container(
      color: t.targetRow,
      padding: const EdgeInsets.only(top: DeckboxSheet._chevHalf),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: chip == null ? DeckboxSheet._peekLabel : DeckboxSheet._peekLabelWithChip,
            child: Padding(
              padding: EdgeInsets.fromLTRB(14, 0, 10, chip == null ? 0 : 8),
              child: Row(children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      const TextSpan(text: 'Scanning to '),
                      TextSpan(text: widget.target.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                      TextSpan(text: ' · ${widget.list.name}'),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PickerTokens.mono(context, size: 11.5, color: t.syncInk),
                  ),
                ),
                // Where a scanning hand can reach it — for switching mid-pile
                // without leaving the camera. **Additions only**, and hidden
                // otherwise rather than greyed: a removal matches what is on
                // Deckbox, printing or generic, so the chip means nothing there.
                // The row keeps its height, so the sheet does not jump.
                if (chip != null && adding)
                  ValueListenableBuilder<bool>(
                    valueListenable: chip,
                    builder: (context, on, _) => AnyPrintingChip(
                      on: on,
                      height: 44,
                      onChanged: (v) => chip.value = v,
                    ),
                  ),
              ]),
            ),
          ),
          SizedBox(
            height: PickerTokens.thumbHeight + DeckboxSheet._chevHalf,
            child: shown == null
                ? Center(
                    child: Text(
                      adding ? 'Nothing to add yet — scan a card.' : 'Nothing to remove yet — scan a card.',
                      style: PickerTokens.mono(context, size: 11, color: t.textFaint),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.only(bottom: DeckboxSheet._chevHalf),
                    child: _stagedRow(model, shown, peek: true),
                  ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Full: management bar, slot, status row
  // ---------------------------------------------------------------------------

  /// The app list's bar, button for button: camera, the list and its counts,
  /// sort and search, select, the gear.
  Widget _mgmtBar(BuildContext context, DeckboxSheetModel model) {
    final t = PickerTokens.of(context);
    final copies = model.copies;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, DeckboxSheet._chevHalf + 8, 10, 8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
      child: Row(children: [
        SheetIconBtn(icon: Icons.camera_alt_rounded, tooltip: 'Back to the camera', onTap: widget.onCollapse),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.list.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: t.text),
              ),
              Text(
                '$copies ${copies == 1 ? 'copy' : 'copies'} · ${model.unique} unique',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PickerTokens.mono(context, size: 10.5),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        SheetIconBtn(
          icon: Icons.search_rounded,
          tooltip: 'Sort and search this list',
          active: _searching,
          onTap: () => setState(() {
            _searching = !_searching;
            if (!_searching) _query = '';
          }),
        ),
        const SizedBox(width: 6),
        SheetIconBtn(
          icon: Icons.checklist_rounded,
          tooltip: 'Select',
          active: _selecting,
          onTap: () => setState(() {
            _selecting = !_selecting;
            _picked.clear();
            _expanded = null;
          }),
        ),
        const SizedBox(width: 6),
        SheetIconBtn(icon: Icons.settings_outlined, tooltip: 'List settings', onTap: _settings),
      ]),
    );
  }

  /// As the app list's slot: *Manual add*, or — sorting and searching — the
  /// search field and the sort.
  Widget _slot(BuildContext context) {
    final t = PickerTokens.of(context);
    if (_selecting) return _selectionBar(context);
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      child: _searching
          ? Row(children: [
              Expanded(child: SheetSearchField(query: _query, onChanged: (q) => setState(() => _query = q))),
              const SizedBox(width: 8),
              SheetIconBtn(icon: Icons.swap_vert_rounded, tooltip: _sort.label, onTap: _pickSort),
            ])
          : SheetTextBtn(label: '+  Manual add', wide: true, onTap: widget.onManualAdd),
    );
  }

  /// Selecting: the count, *Cut to*, *Copy to*, and remove. **Cut** takes
  /// staged rows only — the mirror is Deckbox's, never cut; staging its
  /// removal is. **Copy** takes anything. **Remove** unstages picked staged
  /// rows, and stages picked *On Deckbox* rows to remove — whole rows, from
  /// this list (2026-10-18; it was a dead tap for mirror rows).
  Widget _selectionBar(BuildContext context) {
    final t = PickerTokens.of(context);
    final mirrorPicked = _picked.any((k) => k.startsWith('m'));
    final any = _picked.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: t.accentSoft,
        border: Border(bottom: BorderSide(color: t.accent)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 7, 10, 7),
      child: Row(children: [
        Expanded(
          child: Text(
            '${_picked.length} selected',
            style: PickerTokens.mono(context, size: 11.5, weight: FontWeight.w600, color: t.accent),
          ),
        ),
        SheetTextBtn(label: 'Cut to', onTap: any && !mirrorPicked ? () => _move(cut: true) : null),
        const SizedBox(width: 5),
        SheetTextBtn(label: 'Copy to', onTap: any ? () => _move(cut: false) : null),
        const SizedBox(width: 5),
        SheetIconBtn(
          icon: Icons.delete_outline_rounded,
          tooltip: mirrorPicked ? 'Stage to remove' : 'Unstage',
          danger: true,
          small: true,
          onTap: any ? _removePicked : () {},
        ),
      ]),
    );
  }

  List<StagedChange> get _pickedStaged =>
      [for (final s in widget.staged) if (_picked.contains('s${s.id}')) s];

  Future<void> _move({required bool cut}) async {
    final staged = _pickedStaged;
    final mirror = [for (final e in widget.mirror) if (_picked.contains('m${e.id}')) e];
    final moved = await MoveCardsFlow.run(
      context,
      lines: [
        for (final s in staged) CardLine.fromStaged(s),
        for (final e in mirror) CardLine.fromMirror(e, ExternalDao.countOn(widget.list, e)),
      ],
      cut: cut,
      sourceName: widget.list.name,
      fromDeckbox: widget.list,
      // The opposite section of what is picked: removals offer To add, and
      // additions To remove.
      thisList: [
        if (staged.any((s) => s.direction == 'remove')) ScanTarget.add,
        if (staged.any((s) => s.direction == 'add')) ScanTarget.remove,
      ],
    );
    if (moved && mounted) {
      setState(() {
        _selecting = false;
        _picked.clear();
      });
    }
  }

  Future<void> _removePicked() async {
    final staged = [for (final s in _pickedStaged) s.id];
    final rows = [for (final e in widget.mirror) if (_picked.contains('m${e.id}')) e];
    var took = 0;
    await _dao.transaction(() async {
      await _dao.unstage(staged);
      for (final e in rows) {
        took += await _dao.stageRemoval(list: widget.list, row: e, quantity: ExternalDao.countOn(widget.list, e));
      }
    });
    if (!mounted) return;
    if (rows.isNotEmpty) _toast('Staged $took ${took == 1 ? 'copy' : 'copies'} to remove');
    setState(() {
      _selecting = false;
      _picked.clear();
    });
  }

  /// **The Deckbox row** — the list's standing with Deckbox, and the two
  /// requests: ⟳ pull on the left, *Push* on the right when anything is
  /// staged. Signed out and a failed pull say so here, with their action,
  /// rather than as banners of their own; a pull runs along its bottom edge.
  Widget _statusRow(BuildContext context, DeckboxSheetModel model) {
    final t = PickerTokens.of(context);
    final account = widget.account;
    final list = widget.list;
    final signedOut = account != null && !account.sessionValid;
    final error = list.lastPullError;

    return ListenableBuilder(
      listenable: Listenable.merge([DeckboxSync.instance.pulling, DeckboxSync.instance.pushing]),
      builder: (context, _) {
        final pulling = DeckboxSync.instance.pulling.value.contains(list.id);
        final pushing = DeckboxSync.instance.pushing.value.contains(list.id);
        final n = model.sendable;

        final String status;
        final Color statusColor;
        Widget? action;
        if (signedOut) {
          status = 'Signed out';
          statusColor = t.warning;
          action = _rowAction('Log in', () => logInAgain(context));
        } else if (pulling) {
          status = 'Pulling…';
          statusColor = t.syncInk;
        } else if (error != null) {
          status = "Couldn't read it — $error";
          statusColor = t.warning;
          action = _rowAction('Retry', widget.onPull);
        } else {
          status = [
            ?account?.username,
            list.lastPulledAt == null ? 'not pulled yet' : 'pulled ${pulledAgo(list.lastPulledAt!)}',
            if (model.flagged > 0) '${model.flagged} flagged',
          ].join(' · ');
          statusColor = t.syncInk;
        }

        return Container(
          decoration: BoxDecoration(
            color: t.syncSoft,
            border: Border(bottom: BorderSide(color: t.line)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
              child: Row(children: [
                SheetIconBtn(
                  icon: Icons.sync_rounded,
                  tooltip: 'Pull now',
                  small: true,
                  onTap: signedOut || pulling || pushing ? () {} : widget.onPull,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PickerTokens.mono(context, size: 11, color: statusColor),
                  ),
                ),
                ?action,
                if (pushing || n > 0) ...[
                  const SizedBox(width: 8),
                  SheetTextBtn(
                    label: pushing ? 'Pushing…' : 'Push $n',
                    icon: Icons.cloud_upload_outlined,
                    color: t.sync,
                    onTap: widget.onPush,
                  ),
                ],
              ]),
            ),
            if (pulling)
              LinearProgressIndicator(minHeight: 2, color: t.sync, backgroundColor: t.syncSoft)
            else
              const SizedBox(height: 2),
          ]),
        );
      },
    );
  }

  Widget _rowAction(String label, VoidCallback onTap) => TextButton(
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        onPressed: onTap,
        child: Text(label),
      );

  Future<void> _pickSort() async {
    final t = PickerTokens.of(context);
    final picked = await showModalBottomSheet<DeckboxSort>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final s in DeckboxSort.values)
            ListTile(
              title: Text(s.label),
              trailing: s == _sort ? Icon(Icons.check_rounded, color: t.accent) : null,
              onTap: () => Navigator.of(sheetContext).pop(s),
            ),
        ]),
      ),
    );
    if (picked != null) setState(() => _sort = picked);
  }

  // ---------------------------------------------------------------------------
  // The three sections
  // ---------------------------------------------------------------------------

  List<Widget> _sections(BuildContext context, DeckboxSheetModel model) {
    final t = PickerTokens.of(context);
    final addTarget = widget.target == ScanTarget.add;
    final adds = model.additions;
    final rems = model.removals;
    final mirror = _sort.apply(model.onDeckbox);

    return [
      SliverToBoxAdapter(
        child: DeckboxSectionHeader(
          label: 'To add',
          count: adds.fold(0, (n, a) => n + a.staged.quantity),
          folded: _folded.contains(_Section.add),
          onFold: () => _fold(_Section.add),
          // Selecting hides the target tint; the target is kept, not shown.
          isTarget: addTarget && !_selecting,
          staged: true,
          onTarget: () => widget.onTargetChanged(ScanTarget.add),
          check: _sectionCheck([for (final a in adds) 's${a.staged.id}']),
        ),
      ),
      if (!_folded.contains(_Section.add)) ...[
        SliverList.builder(
          itemCount: adds.length,
          itemBuilder: (context, i) => _stagedRow(model, adds[i].staged),
        ),
      ],
      SliverToBoxAdapter(
        child: DeckboxSectionHeader(
          label: 'To remove',
          count: rems.fold(0, (n, r) => n + r.staged.quantity),
          folded: _folded.contains(_Section.remove),
          onFold: () => _fold(_Section.remove),
          isTarget: !addTarget && !_selecting,
          staged: true,
          onTarget: () => widget.onTargetChanged(ScanTarget.remove),
          tag: model.flagged == 0 ? null : '${model.flagged} flagged',
          check: _sectionCheck([for (final r in rems) 's${r.staged.id}']),
        ),
      ),
      if (!_folded.contains(_Section.remove))
        SliverList.builder(
          itemCount: rems.length,
          itemBuilder: (context, i) => _stagedRow(model, rems[i].staged),
        ),
      SliverToBoxAdapter(
        child: DeckboxSectionHeader(
          label: 'On Deckbox',
          count: model.copies,
          folded: _folded.contains(_Section.deckbox),
          onFold: () => _fold(_Section.deckbox),
          check: _sectionCheck([for (final e in mirror) 'm${e.id}']),
        ),
      ),
      if (!_folded.contains(_Section.deckbox))
        if (mirror.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Text(
                _query.trim().isNotEmpty
                    ? 'Nothing here matches.'
                    : widget.list.lastPulledAt == null
                        ? 'Not pulled yet.'
                        : 'Nothing on this list.',
                textAlign: TextAlign.center,
                style: TextStyle(color: t.textDim),
              ),
            ),
          )
        else
          // Built lazily: an Inventory can hold thousands of rows.
          SliverList.builder(
            itemCount: mirror.length,
            itemBuilder: (context, i) {
              final e = mirror[i];
              final count = model.countOn(e);
              final left = count - (model.removed[e.id] ?? 0);
              return MirrorRow(
                key: ValueKey('m${e.id}'),
                entry: e,
                count: count,
                tradelist: _tradelist,
                listKind: widget.list.kind,
                added: model.added[e.id] ?? 0,
                removed: model.removed[e.id] ?? 0,
                selecting: _selecting,
                selected: _picked.contains('m${e.id}'),
                onTap: () => _selecting ? _togglePick('m${e.id}') : widget.onOpenMirror(e),
                onSwipe: left > 0 ? () => _stageWholeRow(e) : null,
              );
            },
          ),
    ];
  }

  Widget _stagedRow(DeckboxSheetModel model, StagedChange s, {bool peek = false}) {
    final inTarget = (s.direction == 'add') == (widget.target == ScanTarget.add);
    final String pill;
    final PillKind kind;
    String? tradeHalf;
    int? cap;
    if (s.direction == 'add') {
      final a = model.additions.firstWhere((a) => a.staged.id == s.id);
      pill = model.additionPill(a);
      tradeHalf = model.tradeHalf(a);
      kind = s.flag != null ? PillKind.flag : (a.existing == null ? PillKind.newRow : PillKind.more);
      cap = model.markCap(a);
    } else {
      final r = model.removals.firstWhere((r) => r.staged.id == s.id);
      pill = model.removalPill(r);
      kind = s.flag == null && r.row != null ? PillKind.remove : PillKind.flag;
      cap = r.row == null ? null : model.countOn(r.row!);
    }
    return StagedRow(
      key: ValueKey('s${s.id}${peek ? 'p' : ''}'),
      staged: s,
      pill: pill,
      pillKind: kind,
      inTarget: peek || (inTarget && !_selecting),
      selecting: _selecting && !peek,
      selected: _picked.contains('s${s.id}'),
      tradeHalf: tradeHalf,
      listKind: widget.list.kind,
      expanded: _expanded == 's${s.id}',
      pulsing: s.id == widget.pulseStagedId,
      peek: peek,
      maxQuantity: cap,
      // An addition opens its detail, as an app list's row does; a removal
      // has nothing to edit but its count, so it opens its stepper.
      // A Tradelist's addition is a mark on an Inventory row — nothing to
      // edit but its count — so it opens its stepper, as a removal does.
      onTap: () => _selecting && !peek
          ? _togglePick('s${s.id}')
          : s.direction == 'add' && !_tradelist
          ? widget.onOpenStaged(s)
          : peek
              ? _toggle()
              : _expand('s${s.id}'),
      onSetQuantity: (q) => _setQuantity(s, q),
      onUnstage: () => _unstage(s),
    );
  }

  // ---------------------------------------------------------------------------

  Future<void> _settings() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // App-wide, kept across restarts; shown where it matters — the
          // Inventory, whose additions it puts up for trade.
          if (widget.list.kind == 'inventory')
            ValueListenableBuilder<bool>(
              valueListenable: DeckboxPrefs.alsoForTrade,
              builder: (_, on, _) => SwitchListTile(
                secondary: const Icon(Icons.swap_horiz_rounded),
                title: const Text('Also put additions up for trade'),
                subtitle: const Text('Cards staged from now on also go on the Tradelist when pushed'),
                value: on,
                onChanged: DeckboxPrefs.setAlsoForTrade,
              ),
            ),
          if (widget.account case final account?)
            ListTile(
              leading: const Icon(Icons.manage_accounts_outlined),
              title: const Text('Account'),
              subtitle: Text(account.username),
              onTap: () {
                Navigator.of(sheetContext).pop();
                showAccountSheet(context, account);
              },
            ),
        ]),
      ),
    );
  }
}
