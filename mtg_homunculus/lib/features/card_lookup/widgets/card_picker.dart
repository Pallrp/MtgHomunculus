// `Card` here is a printing from the local database, not Material's widget.
import 'dart:async';

import 'package:flutter/material.dart' hide Card;

import '../data/cards_database.dart';
import '../models/scryfall_card.dart';

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

  const PickerResult(this.card, {this.quantity = 1});
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

  const CardPicker({
    super.key,
    required this.scope,
    required this.db,
    this.initial = const [],
    this.inList = const {},
  });

  /// Open as a bottom sheet — [PickerScope.chooseVersion] and
  /// [PickerScope.changeVersion], both of which interrupt something.
  static Future<PickerResult?> showSheet(
    BuildContext context, {
    required PickerScope scope,
    required CardsDatabase db,
    List<Card> initial = const [],
    Set<String> inList = const {},
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
        ),
      );

  /// Open full screen — [PickerScope.manualAdd], which is a destination rather
  /// than an interruption.
  static Future<PickerResult?> showScreen(
    BuildContext context, {
    required CardsDatabase db,
    Set<String> inList = const {},
  }) =>
      Navigator.of(context).push<PickerResult>(MaterialPageRoute(
        builder: (_) => Scaffold(
          body: SafeArea(
            child: CardPicker(
              scope: PickerScope.manualAdd,
              db: db,
              inList: inList,
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

  /// Copies queued per printing, from the tile steppers.
  final Map<String, int> _queued = {};

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
      setState(() => _shown = widget.initial);
      return;
    }
    setState(() => _busy = true);
    final results = await widget.db.search(q);
    if (!mounted) return;
    setState(() {
      _shown = results;
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

  void _bump(Card card, int delta) {
    setState(() {
      final next = (_queued[card.id] ?? 0) + delta;
      if (next <= 0) {
        _queued.remove(card.id);
      } else {
        _queued[card.id] = next;
      }
    });
  }

  // ---------------------------------------------------------------------------

  String get _title => switch (widget.scope) {
        PickerScope.chooseVersion => 'Choose version',
        PickerScope.manualAdd => 'Add a card',
        PickerScope.changeVersion => 'Change version',
      };

  String get _subtitle {
    if (_busy) return 'Searching…';
    if (_shown.isEmpty) {
      return widget.scope == PickerScope.manualAdd
          ? 'Search by name, or name and set'
          : 'No printings found';
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
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_title, style: theme.textTheme.titleMedium),
                Text(
                  _subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: widget.scope == PickerScope.chooseVersion
                ? 'Skip this card'
                : 'Close',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _searchField(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: TextField(
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
            hintText: 'Name, or name and set — "bolt 2xm"',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    onPressed: () {
                      _searchController.clear();
                      _runSearch('');
                    },
                  ),
            border: const OutlineInputBorder(),
          ),
        ),
      );

  Widget _grid() {
    if (_shown.isEmpty) {
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
      itemCount: _shown.length,
      itemBuilder: (context, i) {
        final card = _shown[i];
        return _Tile(
          card: card,
          queued: _queued[card.id] ?? 0,
          inList: widget.inList.contains(card.id),
          onTap: () => Navigator.of(context).pop(
            PickerResult(card, quantity: _queued[card.id] ?? 0),
          ),
          onBump: (d) => _bump(card, d),
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
  final int queued;
  final bool inList;
  final VoidCallback onTap;
  final void Function(int delta) onBump;

  const _Tile({
    required this.card,
    required this.queued,
    required this.inList,
    required this.onTap,
    required this.onBump,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = ScryfallCard.imageUrlFor(card.id, card.imageUpdatedAt);

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
                  child: url == null
                      ? _placeholder(theme, Icons.image_not_supported_outlined)
                      : Image.network(
                          url,
                          fit: BoxFit.cover,
                          loadingBuilder: (c, child, progress) =>
                              progress == null
                                  ? child
                                  : _placeholder(theme, null,
                                      progress: progress),
                          errorBuilder: (c, _, _) =>
                              _placeholder(theme, Icons.wifi_off_rounded),
                        ),
                ),
                if (inList)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: _Badge(
                      icon: Icons.check_rounded,
                      color: theme.colorScheme.primary,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          card.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        Text(
          '${card.setCode.toUpperCase()} · ${card.collectorNumber}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        // The shortcut for "just give me another copy" — it is what makes adding
        // several versions in one visit possible without leaving the grid.
        SizedBox(
          height: 28,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _StepButton(
                icon: Icons.remove_rounded,
                onTap: queued == 0 ? null : () => onBump(-1),
              ),
              Text(
                '$queued',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: queued > 0 ? FontWeight.w700 : FontWeight.w400,
                  color: queued > 0 ? null : theme.disabledColor,
                ),
              ),
              _StepButton(
                icon: Icons.add_rounded,
                onTap: () => onBump(1),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _placeholder(ThemeData theme, IconData? icon,
          {ImageChunkEvent? progress}) =>
      ColoredBox(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Center(
          child: icon != null
              ? Icon(icon, size: 22, color: theme.disabledColor)
              : SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: progress?.expectedTotalBytes == null
                        ? null
                        : progress!.cumulativeBytesLoaded /
                            progress.expectedTotalBytes!,
                  ),
                ),
        ),
      );
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _StepButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) => InkResponse(
        onTap: onTap,
        radius: 18,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            size: 18,
            color: onTap == null
                ? Theme.of(context).disabledColor
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
      );
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _Badge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(icon, size: 12, color: Theme.of(context).colorScheme.onPrimary),
      );
}
