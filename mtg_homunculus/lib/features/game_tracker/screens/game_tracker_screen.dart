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

  // GAMBA roulette state — all screen-local.
  int  _gambaHighlight  = -1;   // player index flashing during spin
  int  _gambaWinner     = -1;   // player index shown with winner border until OK
  bool _gambaAnimating  = false;
  bool _choosingStarter = false;
  final RouletteAnimation _gambaRoulette = RouletteAnimation();

  // Random Player roulette state.
  bool    _randomAnimating = false;
  String? _randomHighlight; // player id flashing during spin
  String? _randomWinner;
  final RouletteAnimation _randomRoulette = RouletteAnimation();

  late final AnimationController _stripCtrl;
  bool _toolbeltOpen = false;

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
    _gambaRoulette.cancel();
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

  void _onCommanderDamage(String defenderId, String attackerId, int delta) {
    setState(() => _game = _game.updateCommanderDamage(defenderId, attackerId, delta));
  }

  void _onNewGame({required List<Player> newPlayers, required int newStartingLife}) {
    _gambaRoulette.cancel();
    _randomRoulette.cancel();
    _closeToolbelt();
    setState(() {
      _game = _game.applySetup(
        newPlayers: newPlayers,
        newStartingLife: newStartingLife,
      );
      _choosingStarter = newPlayers.length > 1;
      _gambaHighlight  = -1;
      _gambaWinner     = -1;
      _gambaAnimating  = false;
      _randomAnimating = false;
      _randomHighlight = null;
      _randomWinner    = null;
    });
  }

  // ---------------------------------------------------------------------------
  // GAMBA
  // ---------------------------------------------------------------------------

  void _onGambaTap() {
    if (_gambaAnimating) return;
    setState(() => _gambaAnimating = true);
    _gambaRoulette.start<int>(
      items: _game.clockwiseOrder,
      onHighlight: (index) => setState(() => _gambaHighlight = index),
      onComplete: (index) => setState(() {
        _gambaAnimating  = false;
        _gambaHighlight  = -1;
        _choosingStarter = false;
        _gambaWinner     = index;
      }),
      isMounted: () => mounted,
    );
  }

  void _confirmGameStart() {
    setState(() => _gambaWinner = -1);
  }

  void _skipGamba() {
    _gambaRoulette.cancel();
    setState(() {
      _choosingStarter = false;
      _gambaHighlight  = -1;
      _gambaAnimating  = false;
    });
  }

  // ---------------------------------------------------------------------------
  // Toolbelt
  // ---------------------------------------------------------------------------

  void _toggleToolbelt() {
    if (_toolbeltOpen) {
      _closeToolbelt();
    } else {
      setState(() => _toolbeltOpen = true);
      _stripCtrl.forward(from: 0);
    }
  }

  void _closeToolbelt() {
    if (!_toolbeltOpen) return;
    _stripCtrl.reverse().then((_) {
      if (mounted) setState(() => _toolbeltOpen = false);
    });
  }

  void _confirmRandomPick() {
    setState(() => _randomWinner = null);
  }

  // ---------------------------------------------------------------------------
  // Random Player roulette
  // ---------------------------------------------------------------------------

  void _startRandomRoulette(List<String> playerIds) {
    if (playerIds.isEmpty) return;

    final ordered = _game.clockwiseOrder
        .map((i) => _game.players[i].id)
        .where(playerIds.contains)
        .toList();

    if (ordered.isEmpty) return;

    if (ordered.length == 1) {
      setState(() => _randomWinner = ordered[0]);
      return;
    }

    setState(() => _randomAnimating = true);
    _randomRoulette.start<String>(
      items: ordered,
      onHighlight: (id) => setState(() => _randomHighlight = id),
      onComplete: (id) => setState(() {
        _randomAnimating = false;
        _randomHighlight = null;
        _randomWinner    = id;
      }),
      isMounted: () => mounted,
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final showDiamond = _game.players.length >= 2;

    return GtSettingsScope(
      settings: widget.settings,
      child: Scaffold(
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
            if (req != null) _closeToolbelt();
          },
          onStartRandomRoulette: _startRandomRoulette,
          child: LayoutBuilder(
            builder: (_, constraints) {
              final centerX  = constraints.maxWidth / 2;
              final availableH = constraints.maxHeight - kSetupStripHeight;
              final centerY  = availableH / 2;

              return AnimatedBuilder(
                animation: _stripCtrl,
                builder: (_, _) {
                  final v       = _stripCtrl.value;
                  final vHeight = availableH * v;

                  return Stack(
                    children: [
                      // Game grid — fills all space above the setup strip.
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: kSetupStripHeight),
                          child: GameGrid(
                            game: _game,
                            choosingStarter: _pickRequest == null && _choosingStarter,
                            gambaHighlightIndex: _gambaHighlight,
                            gambaWinnerIndex: _gambaWinner,
                            playerPickRequest: _pickRequest,
                            onLifeChange: _onLifeChange,
                            onCommanderDamage: _onCommanderDamage,
                            randomAnimating: _randomAnimating,
                            randomHighlightId: _randomHighlight,
                            randomWinnerId: _randomWinner,
                            onConfirmStart: _confirmGameStart,
                            onSkipGamba: _skipGamba,
                          ),
                        ),
                      ),

                      // Vertical toolbelt strip — expands up/down from center.
                      if (v > 0)
                        Positioned(
                          top: centerY - vHeight / 2,
                          height: vHeight,
                          left: centerX - kToolbeltStripHeight / 2,
                          width: kToolbeltStripHeight,
                          child: ToolbeltStrip(
                            animation: _stripCtrl,
                            tools: kToolbeltTools,
                          ),
                        ),

                      // Diamond — centered for 2+ players.
                      if (showDiamond)
                        Positioned(
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
  }

  Widget _diamond() {
    final isPickMode      = _pickRequest != null;
    final isGambaOkPhase  = _gambaWinner != -1;
    final isRandomOkPhase = _randomWinner != null;

    final VoidCallback onTap;
    if (isPickMode) {
      onTap = () {
        final req = _pickRequest!;
        setState(() => _pickRequest = null);
        (req.onDiamondActivate ?? req.onCancel)();
      };
    } else if (isGambaOkPhase) {
      onTap = _confirmGameStart;
    } else if (_choosingStarter) {
      onTap = _onGambaTap;
    } else if (isRandomOkPhase) {
      onTap = _confirmRandomPick;
    } else {
      onTap = _toggleToolbelt;
    }

    final isAnyOkPhase = isGambaOkPhase || isRandomOkPhase;

    return PassDiamond(
      choosingStarter: !isPickMode && _choosingStarter,
      // Show spinner and block taps during either roulette spin.
      gambaAnimating: _gambaAnimating || _randomAnimating,
      overrideLabel: isPickMode
          ? (_pickRequest!.diamondLabel ?? 'Cancel')
          : isAnyOkPhase
              ? 'OK'
              : null,
      icon: (!isPickMode && !_choosingStarter && !isAnyOkPhase && !_randomAnimating)
          ? Icons.handyman
          : null,
      onTap: onTap,
    );
  }
}
