import 'package:flutter/material.dart';
import '../models/game_state.dart';
import '../models/player.dart';
import '../models/roulette_animation.dart';
import '../models/toolbelt_tools.dart';
import '../widgets/game_grid.dart';
import '../widgets/gt_game_scope.dart';
import '../widgets/gt_settings_scope.dart';
import '../widgets/setup_sheet.dart';
import '../widgets/pass_diamond.dart';
import '../widgets/toolbelt_strip.dart';

class GameTrackerScreen extends StatefulWidget {
  final GtSettings settings;
  final VoidCallback? onSettingsTap;
  const GameTrackerScreen({
    super.key,
    this.settings = const GtSettings(),
    this.onSettingsTap,
  });

  @override
  State<GameTrackerScreen> createState() => _GameTrackerScreenState();
}

class _GameTrackerScreenState extends State<GameTrackerScreen>
    with SingleTickerProviderStateMixin {
  GameState _game = GameState.initial();
  PlayerPickRequest? _pickRequest;

  // Index highlighted during the GAMBA roulette animation.
  // -1 means no highlight active.
  int _gambaHighlight = -1;

  // Random Player roulette state.
  // _randomHighlight: player ID flashing during the spin (null = not spinning).
  // _randomWinner:    player ID shown with winner border until "Done" is tapped.
  String? _randomHighlight;
  String? _randomWinner;
  final RouletteAnimation _randomRoulette = RouletteAnimation();

  late final AnimationController _stripCtrl;
  Axis? _openAxis;

  @override
  void initState() {
    super.initState();
    _stripCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
  }

  @override
  void dispose() {
    _stripCtrl.dispose();
    _randomRoulette.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Game state mutations
  // ---------------------------------------------------------------------------

  int _playerIndex(String playerId) =>
      _game.players.indexWhere((p) => p.id == playerId);

  void _onLifeChange(String playerId, int delta) {
    final index = _playerIndex(playerId);
    if (index == -1) return;
    setState(() => _game = _game.updatePlayerLife(index, delta));
  }

  void _onTrackerChange(String playerId, String trackerId, int delta) {
    final index = _playerIndex(playerId);
    if (index == -1) return;
    setState(() => _game = _game.updateTrackerValue(index, trackerId, delta));
  }

  void _onTrackerAdd(String playerId, tracker) {
    final index = _playerIndex(playerId);
    if (index == -1) return;
    setState(() => _game = _game.addTrackerToPlayer(index, tracker));
  }

  void _onTrackerRemove(String playerId, String trackerId) {
    final index = _playerIndex(playerId);
    if (index == -1) return;
    setState(() => _game = _game.removeTrackerFromPlayer(index, trackerId));
  }

  void _onTrackerReorder(String playerId, int oldIndex, int newIndex) {
    final index = _playerIndex(playerId);
    if (index == -1) return;
    setState(() => _game = _game.reorderPlayerTrackers(index, oldIndex, newIndex));
  }

  void _onNewGame({required List<Player> newPlayers, required int newStartingLife}) {
    _randomRoulette.cancel();
    setState(() {
      _randomHighlight = null;
      _randomWinner = null;
      _game = _game.applySetup(
        newPlayers: newPlayers,
        newStartingLife: newStartingLife,
      );
    });
  }

  void _onPass() {
    setState(() => _game = _game.passTurn());
  }

  void _onGamba(int pickedIndex) {
    setState(() {
      _gambaHighlight = -1;
      _game = _game.setActivePlayer(pickedIndex);
    });
  }

  void _onGambaHighlight(int index) {
    setState(() => _gambaHighlight = index);
  }

  void _onCommanderDamage(String defenderId, String attackerId, int delta) {
    setState(() => _game = _game.updateCommanderDamage(defenderId, attackerId, delta));
  }

  void _onPlayerTap(String playerId) {
    final index = _playerIndex(playerId);
    if (index == -1) return;
    setState(() => _game = _game.setActivePlayer(index));
  }

  // ---------------------------------------------------------------------------
  // Toolbelt
  // ---------------------------------------------------------------------------

  void _openToolbelt(Axis axis) {
    if (_openAxis != null) return;
    setState(() => _openAxis = axis);
    _stripCtrl.forward(from: 0);
  }

  void _closeToolbelt() {
    _stripCtrl.reverse().then((_) {
      if (mounted) setState(() => _openAxis = null);
    });
  }

  // ---------------------------------------------------------------------------
  // Random Player roulette
  // ---------------------------------------------------------------------------

  void _startRandomRoulette(List<String> playerIds) {
    if (playerIds.isEmpty) return;

    // Re-order the pool to match clockwise board layout so the highlight
    // sweeps around the table, identical in feel to the GAMBA animation.
    final ordered = _game.clockwiseOrder
        .map((i) => _game.players[i].id)
        .where(playerIds.contains)
        .toList();

    if (ordered.isEmpty) return;

    // Single candidate — no animation needed.
    if (ordered.length == 1) {
      setState(() => _randomWinner = ordered[0]);
      return;
    }

    _randomRoulette.start<String>(
      items: ordered,
      onHighlight: (id) => setState(() => _randomHighlight = id),
      onComplete: (id) => setState(() {
        _randomHighlight = null;
        _randomWinner = id;
      }),
      isMounted: () => mounted,
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isSinglePlayer = _game.players.length == 1;
    // Diamond is hidden for solo — no turn order or GAMBA needed.
    final showDiamond = !isSinglePlayer && (_game.gameStarted || _game.choosingStarter);

    final dn = _game.dayNight;

    Widget screen = GtSettingsScope(
      settings: widget.settings,
      child: Scaffold(
        // Prevent the body from shrinking when the keyboard appears.
        // The SetupSheet strip would otherwise float upward and overlap cards.
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          title: const Text('MtgHomunculus'),
          actions: [
            IconButton(
              icon: const Icon(Icons.apps_rounded),
              tooltip: 'Selection',
              onPressed: () {},
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Settings',
              onPressed: widget.onSettingsTap,
            ),
          ],
        ),
        body: GtGameScope(
          game: _game,
          onGameChanged: (g) => setState(() => _game = g),
          playerPickRequest: _pickRequest,
          onPickRequestChanged: (req) {
            setState(() => _pickRequest = req);
            // Close the toolbelt whenever a pick overlay opens — they
            // occupy the same visual space and would conflict.
            if (req != null && _openAxis != null) _closeToolbelt();
          },
          onStartRandomRoulette: _startRandomRoulette,
          child: LayoutBuilder(
            builder: (_, constraints) {
              // Small margin from screen edges; the diamond overlays the strip
              // in z-order so it's always visible regardless of strip width.
              const halfGap = 0.0;
              // Minimum top/bottom padding for the vertical strip.
              const topGap = 0.0;

              final centerX = constraints.maxWidth / 2;
              final availableH = constraints.maxHeight - kSetupStripHeight;
              final centerY = availableH / 2;

              return AnimatedBuilder(
                animation: _stripCtrl,
                builder: (_, _) {
                  final v = _stripCtrl.value;
                  final hv = _openAxis == Axis.horizontal ? v : 0.0;
                  final vv = _openAxis == Axis.vertical ? v : 0.0;

                  // Strip dimensions expand from zero at center → full size.
                  final hWidth = (constraints.maxWidth - 2 * halfGap) * hv;
                  final vHeight = (availableH - 2 * topGap) * vv;

                  return Stack(
                    children: [
                      // Game grid — fills all space above the setup strip.
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: kSetupStripHeight),
                          child: GameGrid(
                            game: _game,
                            choosingStarter: _pickRequest == null && _game.choosingStarter,
                            gambaHighlightIndex: _gambaHighlight,
                            playerPickRequest: _pickRequest,
                            onLifeChange: _onLifeChange,
                            onTrackerChange: _onTrackerChange,
                            onTrackerAdd: _onTrackerAdd,
                            onTrackerRemove: _onTrackerRemove,
                            onTrackerReorder: _onTrackerReorder,
                            onCommanderDamage: _onCommanderDamage,
                            onPlayerTap: _pickRequest == null && _game.choosingStarter ? _onPlayerTap : null,
                            randomHighlightId: _randomHighlight,
                            randomWinnerId: _randomWinner,
                          ),
                        ),
                      ),

                      // Horizontal toolbelt strip — expands left/right from center.
                      if (hv > 0)
                        Positioned(
                          top: centerY - kToolbeltStripHeight / 2,
                          height: kToolbeltStripHeight,
                          left: centerX - hWidth / 2,
                          width: hWidth,
                          child: ToolbeltStrip(
                            axis: Axis.horizontal,
                            animation: _stripCtrl,
                            tools: kToolbeltTools,
                            onClose: _closeToolbelt,
                          ),
                        ),

                      // Vertical toolbelt strip — expands up/down from center.
                      if (vv > 0)
                        Positioned(
                          top: centerY - vHeight / 2,
                          height: vHeight,
                          left: centerX - kToolbeltStripHeight / 2,
                          width: kToolbeltStripHeight,
                          child: ToolbeltStrip(
                            axis: Axis.vertical,
                            animation: _stripCtrl,
                            tools: kToolbeltTools,
                            onClose: _closeToolbelt,
                          ),
                        ),

                      // Pass / Reset / GAMBA diamond — centered for 2+ players.
                      if (showDiamond)
                        isSinglePlayer
                            ? Positioned(
                                bottom: kSetupStripHeight + 16,
                                left: 0,
                                right: 0,
                                child: Center(child: _diamond()),
                              )
                            : Positioned(
                                top: 0,
                                bottom: kSetupStripHeight,
                                left: 0,
                                right: 0,
                                child: Center(child: _diamond()),
                              ),

                      // Setup sheet — persistent bottom strip that drags up.
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        top: 0,
                        child: SetupSheet(
                          game: _game,
                          onNewGame: _onNewGame,
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );

    if (widget.settings.adaptiveTheme && dn != null) {
      screen = Theme(
        data: dn.isDay ? _gtDayTheme() : _gtNightTheme(),
        child: screen,
      );
    }

    return screen;
  }

  Widget _diamond() {
    final isPickMode    = _pickRequest != null;
    final isRandomDone  = _randomWinner != null;

    // Label priority: pick overlay > random done > normal GAMBA/pass logic.
    final String? overrideLabel = isPickMode
        ? (_pickRequest!.diamondLabel ?? 'Cancel')
        : isRandomDone
            ? 'Done'
            : null;

    // Tap priority: pick overlay > random done > normal pass/toolbelt.
    final VoidCallback onTap;
    if (isPickMode) {
      onTap = () {
        final req = _pickRequest!;
        setState(() => _pickRequest = null);
        // Use tool-specific diamond action when provided, else cancel.
        (req.onDiamondActivate ?? req.onCancel)();
      };
    } else if (isRandomDone) {
      onTap = () => setState(() => _randomWinner = null);
    } else {
      onTap = _onPass;
    }

    return PassDiamond(
      playerOrder: _game.clockwiseOrder,
      choosingStarter: !isPickMode && _game.choosingStarter,
      overrideLabel: overrideLabel,
      onPass: onTap,
      onGamba: _onGamba,
      onGambaHighlight: _onGambaHighlight,
      // Suppress swipe-to-open toolbelt during pick overlay or winner display.
      onSwipe: (isPickMode || isRandomDone) ? null : _openToolbelt,
    );
  }
}

// ---------------------------------------------------------------------------
// Adaptive theme overrides — applied when GtSettings.adaptiveTheme is true.
// Scoped to the game tracker only; no other screen is affected.

ThemeData _gtDayTheme() => ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFFBF3E3),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFFB45309),
        surface: Color(0xFFFBF3E3),
        surfaceContainer: Color(0xFFF5E6C8),
        surfaceContainerHigh: Color(0xFFEDD9A3),
        surfaceContainerHighest: Color(0xFFE5CB7A),
        onSurface: Color(0xFF1A1A1A),
        onSurfaceVariant: Color(0xFF555555),
        outline: Color(0xFF888888),
        outlineVariant: Color(0xFFBBBBBB),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF5E6C8),
        foregroundColor: Color(0xFF1A1A1A),
        titleTextStyle: TextStyle(color: Color(0xFF1A1A1A), fontSize: 18),
        iconTheme: IconThemeData(color: Color(0xFF444444)),
        actionsIconTheme: IconThemeData(color: Color(0xFF555555)),
        elevation: 0,
      ),
    );

ThemeData _gtNightTheme() => ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF1A1A1A),
      colorScheme: ColorScheme.dark(
        primary: Colors.blueGrey.shade700,
        surface: const Color(0xFF1A1A1A),
        surfaceContainer: const Color(0xFF2A2A2A),
        surfaceContainerHigh: const Color(0xFF303030),
        surfaceContainerHighest: const Color(0xFF3A3A3A),
        onSurface: Colors.white,
        onSurfaceVariant: const Color(0xFFBBBBBB),
        outline: const Color(0xFF555555),
        outlineVariant: const Color(0xFF383838),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF242424),
        foregroundColor: Colors.white,
        titleTextStyle: TextStyle(color: Colors.white, fontSize: 18),
        iconTheme: IconThemeData(color: Colors.white70),
        actionsIconTheme: IconThemeData(color: Colors.white70),
        elevation: 0,
      ),
    );
