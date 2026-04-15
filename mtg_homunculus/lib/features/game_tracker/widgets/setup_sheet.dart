import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/game_state.dart';
import '../models/player.dart';

// Height of the always-visible collapsed handle strip.
const double kSetupStripHeight = 44.0;

class SetupSheet extends StatefulWidget {
  final GameState game;
  final void Function({required List<Player> newPlayers, required int newStartingLife}) onNewGame;

  const SetupSheet({
    super.key,
    required this.game,
    required this.onNewGame,
  });

  @override
  State<SetupSheet> createState() => _SetupSheetState();
}

class _SetupSheetState extends State<SetupSheet> {
  final DraggableScrollableController _sheetController = DraggableScrollableController();
  bool _isExpanded = false;

  // Draft state — only committed to GameState when New Game is tapped
  late List<_DraftPlayer> _draftPlayers;
  late int _draftStartingLife;
  late TextEditingController _lifeController;

  @override
  void initState() {
    super.initState();
    _initDraft();
  }

  void _initDraft() {
    _draftPlayers = widget.game.players
        .map((p) => _DraftPlayer(id: p.id, color: p.color, seatPosition: p.seatPosition))
        .toList();
    _draftStartingLife = widget.game.startingLife;
    _lifeController = TextEditingController(text: '$_draftStartingLife');
  }

  @override
  void dispose() {
    _sheetController.dispose();
    _lifeController.dispose();
    super.dispose();
  }

  void _toggleSheet() {
    if (_isExpanded) {
      _sheetController.animateTo(
        _collapsedSize,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _sheetController.animateTo(
        _expandedSize,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  // Actual height of the sheet's parent — set by LayoutBuilder on every build
  // so that _collapsedSize is always a fraction of the real available space,
  // not the full screen height (which is taller by the AppBar + status bar).
  double _availableHeight = 1;

  double get _collapsedSize => kSetupStripHeight / _availableHeight;
  double get _expandedSize  => 0.80;

  // Auto-layout: assign seat positions when adding a player.
  // Even → odd: new player goes to bottomEdge.
  // Odd → even: existing bottomEdge player moves to a side column,
  //             new player goes to the other side.
  void _addPlayer() {
    if (_draftPlayers.length >= 6) return;
    setState(() {
      final currentCount = _draftPlayers.length;
      final color = _nextAvailableColor();

      if (currentCount % 2 == 0) {
        // Even → odd: add at bottom short edge
        _draftPlayers.add(_DraftPlayer(
          id: _newId(),
          color: color,
          seatPosition: SeatPosition.bottomEdge,
        ));
      } else {
        // Odd → even: promote existing bottomEdge player to a side column,
        // then add new player to the other side.
        final edgeIndex = _draftPlayers
            .indexWhere((p) => p.seatPosition == SeatPosition.bottomEdge);
        if (edgeIndex != -1) {
          // Determine which side has fewer players
          final leftCount  = _draftPlayers.where((p) => p.seatPosition == SeatPosition.leftSide).length;
          final rightCount = _draftPlayers.where((p) => p.seatPosition == SeatPosition.rightSide).length;
          final promoteToSide = leftCount <= rightCount
              ? SeatPosition.leftSide
              : SeatPosition.rightSide;
          final newSide = promoteToSide == SeatPosition.leftSide
              ? SeatPosition.rightSide
              : SeatPosition.leftSide;
          _draftPlayers[edgeIndex] = _draftPlayers[edgeIndex].withSeat(promoteToSide);
          _draftPlayers.add(_DraftPlayer(
            id: _newId(),
            color: color,
            seatPosition: newSide,
          ));
        } else {
          // No edge player found — just add to the shorter side
          final leftCount  = _draftPlayers.where((p) => p.seatPosition == SeatPosition.leftSide).length;
          final rightCount = _draftPlayers.where((p) => p.seatPosition == SeatPosition.rightSide).length;
          _draftPlayers.add(_DraftPlayer(
            id: _newId(),
            color: color,
            seatPosition: leftCount <= rightCount
                ? SeatPosition.leftSide
                : SeatPosition.rightSide,
          ));
        }
      }
    });
  }

  void _removePlayer(String id) {
    if (_draftPlayers.length <= 1) return;
    setState(() {
      _draftPlayers.removeWhere((p) => p.id == id);
      // A solo player should always be at bottomEdge (no rotation).
      if (_draftPlayers.length == 1) {
        _draftPlayers[0] = _draftPlayers[0].withSeat(SeatPosition.bottomEdge);
      }
    });
  }

  // Returns the first color from kPlayerColors not already held by a draft player.
  Color _nextAvailableColor() {
    final used = _draftPlayers.map((p) => p.color).toSet();
    return kPlayerColors.firstWhere(
      (c) => !used.contains(c),
      orElse: () => kPlayerColors.last,
    );
  }

  void _updateSeat(String id, SeatPosition seat) {
    setState(() {
      final i = _draftPlayers.indexWhere((p) => p.id == id);
      if (i != -1) _draftPlayers[i] = _draftPlayers[i].withSeat(seat);
    });
  }

  void _onNewGame() {
    final life = int.tryParse(_lifeController.text) ?? _draftStartingLife;
    // Build Player objects from the draft, preserving existing player data
    // (trackers, commanderDamage) where the id matches.
    final existingById = {for (final p in widget.game.players) p.id: p};
    final newPlayers = _draftPlayers.map((d) {
      final existing = existingById[d.id];
      if (existing != null) {
        return existing.copyWith(seatPosition: d.seatPosition);
      }
      // New player — create fresh, commanderDamage will be handled by applySetup
      return Player.create(
        color: d.color,
        startingLife: life,
        seatPosition: d.seatPosition,
      );
    }).toList();
    widget.onNewGame(newPlayers: newPlayers, newStartingLife: life);
    // Collapse the sheet — the game is starting
    _sheetController.animateTo(
      _collapsedSize,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Use the real parent height so _collapsedSize is an accurate fraction.
        // Assigning directly (not via setState) is intentional — this is a
        // layout-derived value, not UI state, and changing it must not trigger
        // an extra rebuild.
        _availableHeight = constraints.maxHeight;
        return _buildSheet();
      },
    );
  }

  Widget _buildSheet() {
    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (n) {
        final expanded = n.extent > (_collapsedSize + 0.05);
        if (expanded != _isExpanded) setState(() => _isExpanded = expanded);
        return false;
      },
      child: DraggableScrollableSheet(
        controller: _sheetController,
        initialChildSize: _collapsedSize,
        minChildSize: _collapsedSize,
        maxChildSize: _expandedSize,
        snap: true,
        snapSizes: [_collapsedSize, _expandedSize],
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF2A2A2A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              _buildHandle(),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: _buildBody(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHandle() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleSheet,
      // Drive the sheet directly on drag so the handle responds to swipes.
      // The SingleChildScrollView body handles collapse-by-scroll when expanded.
      onVerticalDragUpdate: (details) {
        final screenH = MediaQuery.of(context).size.height;
        final delta = -(details.primaryDelta ?? 0) / screenH;
        final newSize = (_sheetController.size + delta)
            .clamp(_collapsedSize, _expandedSize);
        _sheetController.jumpTo(newSize);
      },
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        final midpoint = (_collapsedSize + _expandedSize) / 2;
        final shouldExpand =
            velocity < -100 || (_sheetController.size > midpoint && velocity <= 300);
        _sheetController.animateTo(
          shouldExpand ? _expandedSize : _collapsedSize,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      },
      child: SizedBox(
        height: kSetupStripHeight,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedRotation(
                  turns: _isExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 300),
                  child: Icon(Icons.keyboard_arrow_up_rounded,
                      size: 16, color: Colors.white.withValues(alpha: 0.5)),
                ),
                const SizedBox(width: 4),
                Text(
                  'Setup',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (!_isExpanded) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionLabel('Players'),
          const SizedBox(height: 8),
          _LayoutPreview(
            players: _draftPlayers,
            onRemove: _removePlayer,
            onSeatChange: _updateSeat,
          ),
          const SizedBox(height: 8),
          _buildAddPlayerButton(),
          const SizedBox(height: 20),
          _buildSectionLabel('Starting Life'),
          const SizedBox(height: 8),
          _buildLifeInput(),
          const SizedBox(height: 28),
          _buildNewGameButton(),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String text) => Text(
        text,
        style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 11,
            letterSpacing: 1.2),
      );

  Widget _buildAddPlayerButton() {
    final disabled = _draftPlayers.length >= 6;
    return GestureDetector(
      onTap: disabled ? null : _addPlayer,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: disabled ? 0.04 : 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: Colors.white.withValues(alpha: disabled ? 0.1 : 0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_add_rounded,
                size: 16,
                color: Colors.white.withValues(alpha: disabled ? 0.2 : 0.6)),
            const SizedBox(width: 6),
            Text(
              disabled ? 'Max 6 players' : '+ Add Player',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: disabled ? 0.2 : 0.6),
                  fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLifeInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _lifeController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(color: Colors.white, fontSize: 20),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
              ),
              onChanged: (v) {
                final parsed = int.tryParse(v);
                if (parsed != null) setState(() => _draftStartingLife = parsed);
              },
            ),
          ),
          Column(
            children: [
              _LifeAdjustButton(
                icon: Icons.add,
                onTap: () => setState(() {
                  _draftStartingLife++;
                  _lifeController.text = '$_draftStartingLife';
                }),
              ),
              _LifeAdjustButton(
                icon: Icons.remove,
                onTap: () => setState(() {
                  if (_draftStartingLife > 1) {
                    _draftStartingLife--;
                    _lifeController.text = '$_draftStartingLife';
                  }
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNewGameButton() {
    return GestureDetector(
      onTap: _onNewGame,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.blueGrey.shade700,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text(
            'New Game',
            style: TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}

// Small +/- button in the life input row.
class _LifeAdjustButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _LifeAdjustButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 18, color: Colors.white.withValues(alpha: 0.5)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Draft player — lightweight model for the Setup sheet's local state
// ---------------------------------------------------------------------------
class _DraftPlayer {
  final String id;
  final Color color;
  final SeatPosition seatPosition;

  const _DraftPlayer({
    required this.id,
    required this.color,
    required this.seatPosition,
  });

  _DraftPlayer withSeat(SeatPosition s) =>
      _DraftPlayer(id: id, color: color, seatPosition: s);
}

// ---------------------------------------------------------------------------
// Layout Preview — tall grid with tap-to-remove and long-press drag-to-reposition
// ---------------------------------------------------------------------------
class _LayoutPreview extends StatefulWidget {
  final List<_DraftPlayer> players;
  final void Function(String id) onRemove;
  final void Function(String id, SeatPosition seat) onSeatChange;

  const _LayoutPreview({
    required this.players,
    required this.onRemove,
    required this.onSeatChange,
  });

  @override
  State<_LayoutPreview> createState() => _LayoutPreviewState();
}

class _LayoutPreviewState extends State<_LayoutPreview> {
  bool _isDragging = false;

  bool _isEdgePlayer(_DraftPlayer p) =>
      p.seatPosition == SeatPosition.topEdge ||
      p.seatPosition == SeatPosition.bottomEdge;

  @override
  Widget build(BuildContext context) {
    final topEdge    = widget.players.where((p) => p.seatPosition == SeatPosition.topEdge).toList();
    final bottomEdge = widget.players.where((p) => p.seatPosition == SeatPosition.bottomEdge).toList();
    final leftSide   = widget.players.where((p) => p.seatPosition == SeatPosition.leftSide).toList();
    final rightSide  = widget.players.where((p) => p.seatPosition == SeatPosition.rightSide).toList();
    final sideCount  = leftSide.length + rightSide.length;
    final canRemove  = widget.players.length > 1;

    return Container(
      height: 280,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Stack(
            children: [
              // Grid — mirrors the GameGrid layout
              Column(
                children: [
                  if (topEdge.isNotEmpty)
                    Expanded(
                      flex: 1,
                      child: _buildCard(topEdge.first, canRemove),
                    ),
                  if (sideCount > 0)
                    Expanded(
                      flex: sideCount,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (leftSide.isNotEmpty)
                            Expanded(
                              child: Column(
                                children: leftSide
                                    .map((p) => Expanded(child: _buildCard(p, canRemove)))
                                    .toList(),
                              ),
                            ),
                          if (rightSide.isNotEmpty)
                            Expanded(
                              child: Column(
                                children: rightSide
                                    .map((p) => Expanded(child: _buildCard(p, canRemove)))
                                    .toList(),
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (bottomEdge.isNotEmpty)
                    Expanded(
                      flex: 1,
                      child: _buildCard(bottomEdge.first, canRemove),
                    ),
                ],
              ),
              // Drop zone overlay — only visible while dragging an edge card
              if (_isDragging)
                Positioned.fill(
                  child: _buildDropOverlay(sideCount),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard(_DraftPlayer player, bool canRemove) {
    // Inner card: colored fill + centered trash icon when removable.
    Widget card = Padding(
      padding: const EdgeInsets.all(3),
      child: GestureDetector(
        onTap: canRemove ? () => widget.onRemove(player.id) : null,
        child: Container(
          decoration: BoxDecoration(
            color: player.color.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: player.color.withValues(alpha: 0.7)),
          ),
          child: canRemove
              ? Center(
                  child: Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.white.withValues(alpha: 0.35),
                    size: 18,
                  ),
                )
              : null,
        ),
      ),
    );

    // Side players are not repositionable — return the card as-is.
    if (!_isEdgePlayer(player)) return card;

    // Short-edge players can be long-press dragged to a new seat position.
    return LongPressDraggable<String>(
      data: player.id,
      delay: const Duration(milliseconds: 200),
      onDragStarted: () => setState(() => _isDragging = true),
      onDragEnd: (_) => setState(() => _isDragging = false),
      onDraggableCanceled: (_, _) => setState(() => _isDragging = false),
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 70,
          height: 44,
          child: Container(
            decoration: BoxDecoration(
              color: player.color.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: player.color),
            ),
          ),
        ),
      ),
      childWhenDragging: Padding(
        padding: const EdgeInsets.all(3),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
        ),
      ),
      child: card,
    );
  }

  // Four drop zones shown over the grid while an edge card is being dragged.
  Widget _buildDropOverlay(int sideCount) {
    return Column(
      children: [
        Expanded(
          flex: 2,
          child: _dropTarget(SeatPosition.topEdge, Icons.keyboard_arrow_up_rounded),
        ),
        Expanded(
          flex: sideCount > 0 ? sideCount * 2 : 4,
          child: Row(
            children: [
              Expanded(child: _dropTarget(SeatPosition.leftSide, Icons.keyboard_arrow_left_rounded)),
              Expanded(child: _dropTarget(SeatPosition.rightSide, Icons.keyboard_arrow_right_rounded)),
            ],
          ),
        ),
        Expanded(
          flex: 2,
          child: _dropTarget(SeatPosition.bottomEdge, Icons.keyboard_arrow_down_rounded),
        ),
      ],
    );
  }

  Widget _dropTarget(SeatPosition seat, IconData icon) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) {
        final p = widget.players.firstWhere(
          (pl) => pl.id == details.data,
          orElse: () => widget.players.first,
        );
        return p.seatPosition != seat;
      },
      onAcceptWithDetails: (details) {
        widget.onSeatChange(details.data, seat);
        setState(() => _isDragging = false);
      },
      builder: (_, candidates, _) {
        final hovering = candidates.isNotEmpty;
        return Container(
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: hovering ? 0.15 : 0.04),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.white.withValues(alpha: hovering ? 0.7 : 0.2),
              width: hovering ? 2 : 1,
            ),
          ),
          child: Center(
            child: Icon(
              icon,
              color: Colors.white.withValues(alpha: hovering ? 1.0 : 0.35),
              size: 20,
            ),
          ),
        );
      },
    );
  }
}
