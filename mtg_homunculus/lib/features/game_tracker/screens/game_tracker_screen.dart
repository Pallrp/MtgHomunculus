import 'package:flutter/material.dart';
import '../models/game_state.dart';
import '../widgets/player_card.dart';

class GameTrackerScreen extends StatefulWidget {
  const GameTrackerScreen({super.key});

  @override
  State<GameTrackerScreen> createState() => _GameTrackerScreenState();
}

class _GameTrackerScreenState extends State<GameTrackerScreen> {
  // _game is the single source of truth for the entire screen.
  // Any change to game state goes through setState(() { _game = _game.someMethod(); })
  GameState _game = GameState.initial();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
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
            onPressed: () {}, // [SELECTION] — to be implemented
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white70),
            tooltip: 'Settings',
            onPressed: () {}, // [SETTINGS] — to be implemented
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300, maxHeight: 260),
            child: PlayerCard(
              player: _game.players.first,
              isActive: true,
              onLifeChange: (delta) {
                setState(() {
                  _game = _game.updatePlayerLife(0, delta);
                });
              },
              onTrackerChange: (trackerId, delta) {
                setState(() {
                  _game = _game.updateTrackerValue(0, trackerId, delta);
                });
              },
              onTrackerAdd: (tracker) {
                setState(() {
                  _game = _game.addTrackerToPlayer(0, tracker);
                });
              },
              onTrackerRemove: (trackerId) {
                setState(() {
                  _game = _game.removeTrackerFromPlayer(0, trackerId);
                });
              },
              onTrackerReorder: (oldIndex, newIndex) {
                setState(() {
                  _game = _game.reorderPlayerTrackers(0, oldIndex, newIndex);
                });
              },
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {}, // [MANAGE GAME] — to be implemented
        icon: const Icon(Icons.tune_rounded),
        label: const Text('Manage Game'),
        backgroundColor: const Color(0xFF3A3A3A),
        foregroundColor: Colors.white,
      ),
    );
  }
}
