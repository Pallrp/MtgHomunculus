import 'package:flutter/material.dart';
import '../models/game_state.dart';
import '../models/player.dart';
import '../widgets/game_grid.dart';
import '../widgets/setup_sheet.dart';
import '../widgets/pass_diamond.dart';

class GameTrackerScreen extends StatefulWidget {
  const GameTrackerScreen({super.key});

  @override
  State<GameTrackerScreen> createState() => _GameTrackerScreenState();
}

class _GameTrackerScreenState extends State<GameTrackerScreen> {
  GameState _game = GameState.initial();

  // Index highlighted during the GAMBA roulette animation.
  // -1 means no highlight active.
  int _gambaHighlight = -1;

  // ---------------------------------------------------------------------------
  // Game state mutations
  // ---------------------------------------------------------------------------

  void _onLifeChange(String playerId, int delta) {
    final index = _game.players.indexWhere((p) => p.id == playerId);
    if (index == -1) return;
    setState(() => _game = _game.updatePlayerLife(index, delta));
  }

  void _onTrackerChange(String playerId, String trackerId, int delta) {
    final index = _game.players.indexWhere((p) => p.id == playerId);
    if (index == -1) return;
    setState(() => _game = _game.updateTrackerValue(index, trackerId, delta));
  }

  void _onTrackerAdd(String playerId, tracker) {
    final index = _game.players.indexWhere((p) => p.id == playerId);
    if (index == -1) return;
    setState(() => _game = _game.addTrackerToPlayer(index, tracker));
  }

  void _onTrackerRemove(String playerId, String trackerId) {
    final index = _game.players.indexWhere((p) => p.id == playerId);
    if (index == -1) return;
    setState(() => _game = _game.removeTrackerFromPlayer(index, trackerId));
  }

  void _onTrackerReorder(String playerId, int oldIndex, int newIndex) {
    final index = _game.players.indexWhere((p) => p.id == playerId);
    if (index == -1) return;
    setState(() => _game = _game.reorderPlayerTrackers(index, oldIndex, newIndex));
  }

  void _onNewGame({required List<Player> newPlayers, required int newStartingLife}) {
    setState(() => _game = _game.applySetup(
          newPlayers: newPlayers,
          newStartingLife: newStartingLife,
        ));
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
    final index = _game.players.indexWhere((p) => p.id == playerId);
    if (index == -1) return;
    setState(() => _game = _game.setActivePlayer(index));
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isSinglePlayer = _game.players.length == 1;
    // Diamond is hidden for solo — no turn order or GAMBA needed.
    final showDiamond = !isSinglePlayer && (_game.gameStarted || _game.choosingStarter);

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      // Prevent the body from shrinking when the keyboard appears.
      // The SetupSheet strip would otherwise float upward and overlap cards.
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: const Color(0xFF242424),
        title: const Text(
          'MtgHomunculus',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.apps_rounded, color: Colors.white70),
            tooltip: 'Selection',
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white70),
            tooltip: 'Settings',
            onPressed: () {},
          ),
        ],
      ),
      body: Stack(
        children: [
          // Game grid — fills all space above the setup strip
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.only(bottom: kSetupStripHeight),
              child: GameGrid(
                game: _game,
                choosingStarter: _game.choosingStarter,
                gambaHighlightIndex: _gambaHighlight,
                onLifeChange: _onLifeChange,
                onTrackerChange: _onTrackerChange,
                onTrackerAdd: _onTrackerAdd,
                onTrackerRemove: _onTrackerRemove,
                onTrackerReorder: _onTrackerReorder,
                onCommanderDamage: _onCommanderDamage,
                onPlayerTap: _game.choosingStarter ? _onPlayerTap : null,
              ),
            ),
          ),

          // Pass / Reset / GAMBA diamond — centered for 2+ players,
          // above setup strip for single player
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

          // Setup sheet — persistent bottom strip that drags up
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
      ),
    );
  }

  Widget _diamond() => PassDiamond(
        playerCount: _game.players.length,
        choosingStarter: _game.choosingStarter,
        onPass: _onPass,
        onGamba: _onGamba,
        onGambaHighlight: _onGambaHighlight,
      );
}
