import 'package:flutter/material.dart';
import 'player.dart';

// Default color palette — one per player slot (supports up to 6 players)
const List<Color> kPlayerColors = [
  Color(0xFF4A90D9), // blue
  Color(0xFFE74C3C), // red
  Color(0xFF27AE60), // green
  Color(0xFF8E44AD), // purple
  Color(0xFFE67E22), // orange
  Color(0xFF16A085), // teal
];

class GameState {
  final List<Player> players;
  final int startingLife;
  final int activePlayerIndex;
  final bool gameStarted;

  const GameState({
    required this.players,
    this.startingLife = 40,
    this.activePlayerIndex = 0,
    this.gameStarted = false,
  });

  // The state the app opens with: one player, 40 starting life
  factory GameState.initial() => GameState(
        players: [
          Player.create(color: kPlayerColors[0], startingLife: 40),
        ],
      );

  GameState copyWith({
    List<Player>? players,
    int? startingLife,
    int? activePlayerIndex,
    bool? gameStarted,
  }) =>
      GameState(
        players: players ?? this.players,
        startingLife: startingLife ?? this.startingLife,
        activePlayerIndex: activePlayerIndex ?? this.activePlayerIndex,
        gameStarted: gameStarted ?? this.gameStarted,
      );

  // Advance to next player; reset all non-permanent trackers on every player
  GameState passTurn() {
    final nextIndex = (activePlayerIndex + 1) % players.length;
    final updated = players
        .map((p) => p.copyWith(
              trackers: p.trackers
                  .map((t) => t.permanent ? t : t.reset())
                  .toList(),
            ))
        .toList();
    return copyWith(players: updated, activePlayerIndex: nextIndex);
  }

  // Adjust one player's life total by delta (positive or negative)
  GameState updatePlayerLife(int playerIndex, int delta) {
    final updated = List<Player>.from(players);
    updated[playerIndex] = players[playerIndex].copyWith(
      lifeTotal: players[playerIndex].lifeTotal + delta,
    );
    return copyWith(players: updated);
  }

  // Keep the same players and colors but reset life totals and non-permanent trackers
  GameState resetGame() => GameState(
        players: players
            .map((p) => p.copyWith(
                  lifeTotal: startingLife,
                  trackers: p.trackers
                      .where((t) => t.permanent)
                      .map((t) => t.reset())
                      .toList(),
                ))
            .toList(),
        startingLife: startingLife,
      );
}
