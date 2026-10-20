// `Card` here is a printing from the local database, not Material's widget.
import 'dart:async';

import 'package:flutter/material.dart' hide Card;

import '../data/cards_database.dart';
import '../models/scryfall_card.dart';
import '../theme/picker_tokens.dart';
import 'any_printing_chip.dart';
import 'card_thumb.dart';

/// Which question the grid is being opened to answer.
///
/// **Not three screens.** Ambiguity resolution, manual add and change-printing
/// are one grid with a different starting filter, because they are the same act
/// — look at cards, pick the one in your hand — and building three surfaces
/// would mean three places for that act to drift apart.
enum PickerScope {
  /// A scan returned several candidates and the card is not added until this is
  /// answered. See `single_card_capture_flow.md`.
  chooseVersion,

  /// The scanner never saw it. Starts empty: there is nothing to filter to.
  manualAdd,

  /// Correcting a printing already in the list.
  changeVersion,
}

/// What the picker was closed with.
class PickerResult {
  final Card card;

  /// How many copies to add. Zero when the user tapped through to detail rather
  /// than using the tile's stepper.
  final int quantity;

  /// The card, not a printing — a Deckbox Wishlist's *Any printing*. [card]
  /// is then only its representative printing: art, and matching later scans.
  final bool anyPrinting;

  const PickerResult(this.card, {this.quantity = 1, this.anyPrinting = false});
}

/// One grid tile: a printing, or — [any] — a card in any printing.
typedef _TileItem = ({Card card, bool any});

/// Where Manual Add's tile steppers write: **straight into the list** the
/// picker was opened for (decided 2026-10-16). The count on a tile is what
/// that list holds of it; **+** adds one, **−** takes one back, and the picker
/// stays open for the next card.
///
/// Without a sink the steppers queue copies for the tap, as before.
class PickerSink {
  const PickerSink({required this.count, required this.bump});

  /// Copies of [card] — or, `any`, of the card in any printing — in the list.
  final int Function(Card card, bool any) count;

  /// One more (`delta` 1) or one fewer (−1). Returns the new count.
  final Future<int> Function(Card card, bool any, int delta) bump;
}

/// One grid, three scopes.
///
/// Two columns in every scope, art-forward. A thumbnail cannot do this job: the
/// user is holding a physical card and checking whether the thing on screen is
/// the same one, which needs the whole card at a size where frame, art and
/// border read clearly.
class CardPicker extends StatefulWidget {
  final PickerScope scope;
  final CardsDatabase db;

  /// Starting candidates. Empty for [PickerScope.manualAdd].
  final List<Card> initial;

  /// Printings already in the active list, for the in-list badge.
  final Set<String> inList;

  /// A Deckbox Wishlist's *Any printing* setting (M3). Non-null shows the chip:
  /// on, the grid has **one tile per card** and picking one adds the card in
  /// any printing. The picker writes it back when flipped.
  final ValueNotifier<bool>? anyPrinting;

  /// [PickerScope.changeVersion] on a Wishlist row: an *Any printing* tile
  /// first, marked current when [currentAny].
  final bool offerAny;
  final bool currentAny;

  /// Who the picker is adding for — *PlalBulk · Wishlist* — under the title.
  final String? subtitle;

  /// In place of the scope's own title — *Remove a card*.
  final String? title;

  /// **List only** — a Deckbox list's Manual Add into *To remove*: a text
  /// filter over what is on the list. Only these printings show, and one
  /// *Any printing* tile per card with a generic row; nothing else.
  final ({Set<String> printings, Set<String> anyNames})? onlyOn;

  /// Where the tile steppers write — see [PickerSink].
  final PickerSink? sink;

  const CardPicker({
    super.key,
    required this.scope,
    required this.db,
    this.initial = const [],
    this.inList = const {},
    this.anyPrinting,
    this.offerAny = false,
    this.currentAny = false,
    this.subtitle,
    this.title,
    this.onlyOn,
    this.sink,
  });

  /// Open as a bottom sheet — [PickerScope.chooseVersion] and
  /// [PickerScope.changeVersion], both of which interrupt something.
  static Future<PickerResult?> showSheet(
    BuildContext context, {
    required PickerScope scope,
    required CardsDatabase db,
    List<Card> initial = const [],
    Set<String> inList = const {},
    bool offerAny = false,
    bool currentAny = false,
  }) =>
      showModalBottomSheet<PickerResult>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => CardPicker(
          scope: scope,
          db: db,
          initial: initial,
          inList: inList,
          offerAny: offerAny,
          currentAny: currentAny,
        ),
      );

  /// Open full screen — [PickerScope.manualAdd], which is a destination rather
  /// than an interruption.
  static Future<PickerResult?> showScreen(
    BuildContext context, {
    required CardsDatabase db,
    Set<String> inList = const {},
    ValueNotifier<bool>? anyPrinting,
    String? subtitle,
    String? title,
    ({Set<String> printings, Set<String> anyNames})? onlyOn,
    PickerSink? sink,
  }) =>
      Navigator.of(context).push<PickerResult>(MaterialPageRoute(
        builder: (_) => Scaffold(
          body: SafeArea(
            child: CardPicker(
              scope: PickerScope.manualAdd,
              db: db,
              inList: inList,
              anyPrinting: anyPrinting,
              subtitle: subtitle,
              title: title,
              onlyOn: onlyOn,
              sink: sink,
            ),
          ),
        ),
      ));

  @override
  State<CardPicker> createState() => _CardPickerState();
}

class _CardPickerState extends State<CardPicker> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  late List<Card> _shown = widget.initial;
  bool _widened = false;
  bool _busy = false;

  /// The query names a set — `forest lci` — so a printing is wanted, and the
  /// *Any printing* chip greys out.
  bool _querySet = false;

  bool get _anyMode => (widget.anyPrinting?.value ?? false) && !_querySet;

  /// What the grid shows. In *Any printing* mode, the first (newest) printing
  /// of each card stands for it; on a Wishlist row's Change Version, *Any
  /// printing* leads.
  List<_TileItem> get _tiles {
    final only = widget.onlyOn;
    if (only != null) {
      final seen = <String>{};
      return [
        for (final c in _shown) ...[
          if (only.anyNames.contains(c.name) && seen.add(c.name)) (card: c, any: true),
          if (only.printings.contains(c.id)) (card: c, any: false),
        ],
      ];
    }
    if (_anyMode) {
      final seen = <String>{};
      return [
        for (final c in _shown)
          if (seen.add(c.name)) (card: c, any: true),
      ];
    }
    return [
      if (widget.offerAny && !_querySet && _shown.isNotEmpty) (card: _shown.first, any: true),
      for (final c in _shown) (card: c, any: false),
    ];
  }

  static String _key(_TileItem t) => t.any ? 'any:${t.card.name}' : t.card.id;

  /// Copies queued per printing, from the tile steppers — without a sink.
  final Map<String, int> _queued = {};

  /// With a sink: each tile's count as the list reported it after a step,
  /// and the tiles with a step in flight (a double tap is one step).
  final Map<String, int> _counts = {};
  final Set<String> _stepping = {};

  int _countOf(_TileItem t) {
    final sink = widget.sink;
    final key = _key(t);
    return sink == null ? _queued[key] ?? 0 : _counts[key] ?? sink.count(t.card, t.any);
  }

  Future<void> _step(_TileItem t, int delta) async {
    final key = _key(t);
    final sink = widget.sink;
    if (sink == null) return _bump(key, delta);
    if (!_stepping.add(key)) return;
    try {
      final n = await sink.bump(t.card, t.any, delta);
      if (mounted) setState(() => _counts[key] = n);
    } finally {
      _stepping.remove(key);
    }
  }

  /// A tile tapped. With a sink, it adds one — unless its stepper was already
  /// used on this visit, which said how many — and closes.
  Future<void> _choose(_TileItem t) async {
    if (widget.sink == null) {
      Navigator.of(context).pop(
        PickerResult(t.card, quantity: _queued[_key(t)] ?? 0, anyPrinting: t.any),
      );
      return;
    }
    if (!_counts.containsKey(_key(t))) await _step(t, 1);
    if (mounted) Navigator.of(context).pop();
  }

  /// The query is local and cheap; this only stops the grid rebuilding on every
  /// keystroke.
  static const _debounceFor = Duration(milliseconds: 250);

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------

  void _onQueryChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(_debounceFor, () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    if (q.trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        _shown = widget.initial;
        _querySet = false;
      });
      return;
    }
    setState(() => _busy = true);
    final parsed = await widget.db.parseQuery(q);
    // One tile per card wants many printings behind it: a name like "forest"
    // has hundreds, and sixty would show only a few cards.
    final wide = widget.anyPrinting != null || widget.onlyOn != null;
    final results = await widget.db.search(q, limit: wide ? 600 : 60);
    if (!mounted) return;
    setState(() {
      _shown = results;
      _querySet = parsed.setCode != null;
      _widened = true;
      _busy = false;
    });
  }

  /// Widen to every printing of the names already on screen.
  ///
  /// The escape for when the right printing is not among the candidates —
  /// usually because a collector number was misread rather than unread, so the
  /// wrong printings scored highest.
  Future<void> _moreVersions() async {
    if (_widened || _shown.isEmpty) return;
    setState(() => _busy = true);
    final all = <Card>[];
    for (final n in {for (final c in _shown) c.name}) {
      all.addAll(await widget.db.printingsOf(n));
    }
    if (!mounted) return;
    setState(() {
      _shown = all;
      _widened = true;
      _busy = false;
    });
  }

  void _bump(String key, int delta) {
    setState(() {
      final next = (_queued[key] ?? 0) + delta;
      if (next <= 0) {
        _queued.remove(key);
      } else {
        _queued[key] = next;
      }
    });
  }

  // ---------------------------------------------------------------------------

  String get _title => widget.title ?? switch (widget.scope) {
        PickerScope.chooseVersion => 'Choose version',
        PickerScope.manualAdd => 'Add a card',
        PickerScope.changeVersion => 'Change version',
      };

  String get _subtitle {
    if (_busy) return 'Searching…';
    if (widget.onlyOn != null) {
      if (_searchController.text.trim().isEmpty) return 'Search what is on this list';
      final n = _tiles.length;
      return n == 0 ? 'Nothing on this list matches' : '$n on this list';
    }
    if (_shown.isEmpty) {
      return widget.scope == PickerScope.manualAdd
          ? 'Search by name, or name and set'
          : 'No printings found';
    }
    if (_anyMode) {
      final n = _tiles.length;
      return '$n ${n == 1 ? 'card' : 'cards'} · one tile each';
    }
    if (_widened) return '${_shown.length} printings';
    return '${_shown.length} possible matches';
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
      children: [
        _header(context),
        _searchField(context),
        if (widget.anyPrinting != null) _anyRow(context),
        Expanded(child: _grid()),
        if (widget.scope == PickerScope.chooseVersion) _escapes(context),
      ],
    );

    // Manual add is a destination and owns its whole screen; the other two
    // interrupt something and stay draggable over it.
    if (widget.scope == PickerScope.manualAdd) return body;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      maxChildSize: 0.94,
      minChildSize: 0.4,
      builder: (context, _) => body,
    );
  }

  Widget _header(BuildContext context) {
    final t = PickerTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.line)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: t.text,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  [?widget.subtitle, _subtitle].join(' · '),
                  style: PickerTokens.mono(context, size: 11),
                ),
              ],
            ),
          ),
          _SquareButton(
            icon: Icons.close_rounded,
            tooltip: widget.scope == PickerScope.chooseVersion
                ? 'Skip this card'
                : 'Close',
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _searchField(BuildContext context) {
    final t = PickerTokens.of(context);
    return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: TextField(
          style: PickerTokens.mono(context, size: 13, color: t.text),
          controller: _searchController,
          autofocus: widget.scope == PickerScope.manualAdd,
          textInputAction: TextInputAction.search,
          onChanged: _onQueryChanged,
          onSubmitted: (q) {
            _debounce?.cancel();
            _runSearch(q);
          },
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: t.surface2,
            hintText: 'Name, or name and set — "bolt 2xm"',
            hintStyle: PickerTokens.mono(context, size: 12, color: t.textFaint),
            prefixIcon: Icon(Icons.search_rounded, size: 18, color: t.textFaint),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 34, minHeight: 34),
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    icon: Icon(Icons.clear_rounded, size: 16, color: t.textDim),
                    onPressed: () {
                      _searchController.clear();
                      _runSearch('');
                    },
                  ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(PickerTokens.radiusSmall),
              borderSide: BorderSide(color: t.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(PickerTokens.radiusSmall),
              borderSide: BorderSide(color: t.accent),
            ),
          ),
        ),
      );
  }

  /// The *Any printing* chip and what it means right now.
  Widget _anyRow(BuildContext context) {
    final t = PickerTokens.of(context);
    final on = widget.anyPrinting!.value;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(children: [
        AnyPrintingChip(
          on: on,
          enabled: !_querySet,
          onChanged: (v) => setState(() => widget.anyPrinting!.value = v),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            _querySet
                ? 'A set code picks a printing'
                : on
                    ? 'Adds any printing — scans too'
                    : 'Adds the exact printing',
            style: TextStyle(fontSize: 12.5, color: t.textDim),
          ),
        ),
      ]),
    );
  }

  Widget _grid() {
    if (_tiles.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      );
    }

    // `GridView.builder` is the lazy-load-by-viewport measure: a 60-result query
    // costs the images actually on screen, not sixty of them.
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        // Card art is 0.716; the rest is the two text lines and the stepper.
        childAspectRatio: 0.50,
      ),
      itemCount: _tiles.length,
      itemBuilder: (context, i) {
        final tile = _tiles[i];
        return _Tile(
          card: tile.card,
          any: tile.any,
          anyNote: tile.any && widget.offerAny
              ? 'Any of ${_shown.length}${widget.currentAny ? ' · current' : ''}'
              : null,
          queued: _countOf(tile),
          inList: !tile.any && widget.inList.contains(tile.card.id),
          onTap: () => _choose(tile),
          onBump: (d) => _step(tile, d),
        );
      },
    );
  }

  Widget _escapes(BuildContext context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  icon: _busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.grid_view_rounded, size: 18),
                  label: Text(_widened ? 'All printings' : 'More versions'),
                  onPressed: _widened || _busy ? null : _moreVersions,
                ),
              ),
            ],
          ),
        ),
      );
}

// ---------------------------------------------------------------------------

/// Art for the gross match, text for the precise one.
///
/// The `SET · COLLECTOR` line is not decoration. The hardest case is two
/// printings with identical art separated only by a set symbol a few pixels
/// across — nobody can verify that visually — but the collector number is
/// printed on the card in the user's hand, so they match the *text* while the
/// art confirms they are in the right neighbourhood.
class _Tile extends StatelessWidget {
  final Card card;

  /// The card in any printing: an *ANY* badge, and *Any printing* where the
  /// set line would be.
  final bool any;
  final String? anyNote;
  final int queued;
  final bool inList;
  final VoidCallback onTap;
  final void Function(int delta) onBump;

  const _Tile({
    required this.card,
    required this.any,
    required this.queued,
    required this.inList,
    required this.onTap,
    required this.onBump,
    this.anyNote,
  });

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    // `small` (146 × 204), not `normal`. A tile is ~160 dp, so a 1080-wide
    // phone draws it with ~480 physical pixels and `normal` is the sharper fit
    // — but measured side by side the softness is acceptable for what a tile is
    // for, telling one printing from another, and `normal` costs 7× the bytes.
    // At one cache budget that is ~3,500 thumbnails against ~480, which is the
    // difference between a cache that survives a browsing session and one that
    // evicts what you looked at a minute ago.
    final url =
        ScryfallCard.imageUrlFor(card.id, card.imageUpdatedAt, size: 'small');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  // No load-progress spinner any more: at ~12 KB, and served
                  // from disk on a repeat search, there is nothing to report.
                  child: CardThumb(url: url, iconSize: 22),
                ),
                // A pill reading IN LIST, not a tick. A tick means "selected",
                // which is close enough to be misread and means the opposite.
                if (inList)
                  Positioned(top: 5, left: 5, child: _InListPill(tokens: t)),
                if (any)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: t.sync,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'ANY',
                        style: PickerTokens.mono(context, size: 10, weight: FontWeight.w600, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          card.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            height: 1.25,
            color: t.text,
          ),
        ),
        if (any)
          Text(
            anyNote ?? 'Any printing',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: t.syncInk),
          )
        else
          Text(
            '${card.setCode.toUpperCase()} · ${card.collectorNumber}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PickerTokens.mono(context, size: 10.5),
          ),
        // The shortcut for "just give me another copy" — it is what makes adding
        // several versions in one visit possible without leaving the grid.
        const SizedBox(height: 4),
        Row(
          children: [
            _StepButton(
              icon: Icons.remove_rounded,
              onTap: queued == 0 ? null : () => onBump(-1),
            ),
            Expanded(
              child: Center(
                child: Text(
                  '$queued',
                  style: PickerTokens.mono(
                    context,
                    size: 12,
                    weight: queued > 0 ? FontWeight.w600 : FontWeight.w400,
                    color: queued > 0 ? t.text : t.textFaint,
                  ),
                ),
              ),
            ),
            _StepButton(icon: Icons.add_rounded, onTap: () => onBump(1)),
          ],
        ),
      ],
    );
  }

}

/// The square tap target the artifact uses wherever a value is nudged.
class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _StepButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: t.surface2,
          border: Border.all(color: t.line),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Icon(icon, size: 15, color: onTap == null ? t.textFaint : t.text),
      ),
    );
  }
}

class _SquareButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _SquareButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PickerTokens.radiusSmall),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: t.surface2,
            border: Border.all(color: t.line),
            borderRadius: BorderRadius.circular(PickerTokens.radiusSmall),
          ),
          child: Icon(icon, size: 16, color: t.textDim),
        ),
      ),
    );
  }
}

class _InListPill extends StatelessWidget {
  final PickerTokens tokens;
  const _InListPill({required this.tokens});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: tokens.accent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          'IN LIST',
          style: PickerTokens.mono(
            context,
            size: 9,
            weight: FontWeight.w600,
            color: tokens.ground,
          ),
        ),
      );
}
