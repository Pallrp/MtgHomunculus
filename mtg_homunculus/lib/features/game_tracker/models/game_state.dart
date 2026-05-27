import 'package:flutter/material.dart';
import 'game_effect.dart';
import 'player.dart';
import 'tracker.dart';

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
  final bool choosingStarter;
  final List<GameEffect> effects;

  const GameState({
    required this.players,
    this.startingLife = 40,
    this.activePlayerIndex = 0,
    this.gameStarted = false,
    this.choosingStarter = false,
    this.effects = const [],
  });

  // The state the app opens with: one player, not yet started.
  // bottomEdge = no rotation, card faces up — correct for a solo user
  // holding the phone normally.
  factory GameState.initial() => GameState(
        players: [
          Player.create(
            color: kPlayerColors[0],
            startingLife: 40,
            seatPosition: SeatPosition.bottomEdge,
          ),
        ],
      );

  GameState copyWith({
    List<Player>? players,
    int? startingLife,
    int? activePlayerIndex,
    bool? gameStarted,
    bool? choosingStarter,
    List<GameEffect>? effects,
  }) =>
      GameState(
        players: players ?? this.players,
        startingLife: startingLife ?? this.startingLife,
        activePlayerIndex: activePlayerIndex ?? this.activePlayerIndex,
        gameStarted: gameStarted ?? this.gameStarted,
        choosingStarter: choosingStarter ?? this.choosingStarter,
        effects: effects ?? this.effects,
      );

  // ---------------------------------------------------------------------------
  // ---------------------------------------------------------------------------
  // Effect helpers
  // ---------------------------------------------------------------------------

  // Replace any existing effect of the same runtime type, then append.
  GameState setEffect(GameEffect effect) {
    final rest = effects.where((e) => e.runtimeType != effect.runtimeType).toList();
    return copyWith(effects: [...rest, effect]);
  }

  GameState clearEffect<T extends GameEffect>() =>
      copyWith(effects: effects.where((e) => e is! T).toList());

  // Pre-filtered list for one player — passed to PlayerCard by GameGrid.
  List<PlayerEffect> effectsForPlayer(String playerId) =>
      effects.whereType<PlayerEffect>().where((e) => e.playerId == playerId).toList();

  GameState _applyTurnPassedToEffects() {
    final updated = effects
        .map((e) => e.onTurnPassed())
        .whereType<GameEffect>()
        .toList();
    return copyWith(effects: updated);
  }

  DayNightEffect? get dayNight => effects.whereType<DayNightEffect>().firstOrNull;
  StormEffect?    get storm    => effects.whereType<StormEffect>().firstOrNull;

  // ---------------------------------------------------------------------------
  // Player management
  // ---------------------------------------------------------------------------

  // Add a new player. Assigns the next available color, updates all
  // commanderDamage maps to include the new player (and vice versa).
  GameState addPlayer(SeatPosition seatPosition) {
    assert(players.length < 6, 'Cannot have more than 6 players');
    final color = kPlayerColors[players.length];
    final newPlayer = Player.create(
      color: color,
      startingLife: startingLife,
      seatPosition: seatPosition,
      // Initialise damage from every existing player to 0
      commanderDamage: {for (final p in players) p.id: 0},
    );
    // Add the new player's id to every existing player's commanderDamage map
    final updated = players
        .map((p) => p.copyWith(
              commanderDamage: {...p.commanderDamage, newPlayer.id: 0},
            ))
        .toList();
    return copyWith(players: [...updated, newPlayer]);
  }

  // Remove a player by id. Cleans up commanderDamage entries in all other players.
  // Adjusts activePlayerIndex if needed.
  GameState removePlayer(String playerId) {
    assert(players.length > 1, 'Cannot remove the last player');
    final updated = players
        .where((p) => p.id != playerId)
        .map((p) {
          final newDamage = Map<String, int>.from(p.commanderDamage)
            ..remove(playerId);
          return p.copyWith(commanderDamage: newDamage);
        })
        .toList();
    final removedIndex = players.indexWhere((p) => p.id == playerId);
    final newActiveIndex = activePlayerIndex >= updated.length
        ? updated.length - 1
        : (removedIndex <= activePlayerIndex && activePlayerIndex > 0)
            ? activePlayerIndex - 1
            : activePlayerIndex;
    return copyWith(players: updated, activePlayerIndex: newActiveIndex);
  }

  // Update the seat position of a player.
  GameState updatePlayerSeat(String playerId, SeatPosition seatPosition) {
    final updated = players
        .map((p) => p.id == playerId ? p.copyWith(seatPosition: seatPosition) : p)
        .toList();
    return copyWith(players: updated);
  }

  // ---------------------------------------------------------------------------
  // Life & tracker changes
  // ---------------------------------------------------------------------------

  GameState updatePlayerLife(int playerIndex, int delta) {
    final updated = List<Player>.from(players);
    updated[playerIndex] = players[playerIndex].copyWith(
      lifeTotal: players[playerIndex].lifeTotal + delta,
    );
    return copyWith(players: updated);
  }

  GameState updateTrackerValue(int playerIndex, String trackerId, int delta) {
    final player = players[playerIndex];
    final updatedTrackers = player.trackers
        .map((t) => t.id == trackerId ? t.copyWith(value: t.value + delta) : t)
        .toList();
    final updated = List<Player>.from(players);
    updated[playerIndex] = player.copyWith(trackers: updatedTrackers);
    return copyWith(players: updated);
  }

  // ---------------------------------------------------------------------------
  // Commander damage
  // ---------------------------------------------------------------------------

  // Adjust commander damage received by [defenderId] from [attackerId].
  // Also adjusts the defender's life total by the same delta.
  GameState updateCommanderDamage(String defenderId, String attackerId, int delta) {
    final updated = players.map((p) {
      if (p.id == defenderId) {
        final newDamage = Map<String, int>.from(p.commanderDamage);
        newDamage[attackerId] = (newDamage[attackerId] ?? 0) + delta;
        return p.copyWith(
          commanderDamage: newDamage,
          lifeTotal: p.lifeTotal - delta,
        );
      }
      return p;
    }).toList();
    return copyWith(players: updated);
  }

  // ---------------------------------------------------------------------------
  // Tracker list management
  // ---------------------------------------------------------------------------

  GameState addTrackerToPlayer(int playerIndex, Tracker tracker) {
    final updated = List<Player>.from(players);
    final player = players[playerIndex];
    updated[playerIndex] = player.copyWith(
      trackers: [...player.trackers, tracker],
    );
    return copyWith(players: updated);
  }

  GameState removeTrackerFromPlayer(int playerIndex, String trackerId) {
    final updated = List<Player>.from(players);
    final player = players[playerIndex];
    updated[playerIndex] = player.copyWith(
      trackers: player.trackers.where((t) => t.id != trackerId).toList(),
    );
    return copyWith(players: updated);
  }

  GameState reorderPlayerTrackers(int playerIndex, int oldIndex, int newIndex) {
    final updated = List<Player>.from(players);
    final player = players[playerIndex];
    final trackers = List<Tracker>.from(player.trackers);
    final item = trackers.removeAt(oldIndex);
    trackers.insert(newIndex, item);
    updated[playerIndex] = player.copyWith(trackers: trackers);
    return copyWith(players: updated);
  }

  // ---------------------------------------------------------------------------
  // Turn & game flow
  // ---------------------------------------------------------------------------

  // Player indices ordered clockwise around the table:
  // top edge → right side (top→bottom) → bottom edge → left side (bottom→top).
  List<int> get clockwiseOrder {
    List<int> byPos(SeatPosition pos) => players
        .asMap()
        .entries
        .where((e) => e.value.seatPosition == pos)
        .map((e) => e.key)
        .toList();
    return [
      ...byPos(SeatPosition.topEdge),
      ...byPos(SeatPosition.rightSide),
      ...byPos(SeatPosition.bottomEdge),
      ...byPos(SeatPosition.leftSide).reversed,
    ];
  }

  // Advance to next player in clockwise order; reset all non-permanent trackers.
  GameState passTurn() {
    final order = clockwiseOrder;
    final pos   = order.indexOf(activePlayerIndex);
    final nextIndex = order[(pos + 1) % order.length];
    final updated = players
        .map((p) => p.copyWith(
              trackers: p.trackers
                  .map((t) => t.permanent ? t : t.reset())
                  .toList(),
            ))
        .toList();
    return copyWith(players: updated, activePlayerIndex: nextIndex)
        ._applyTurnPassedToEffects();
  }

  // Set the active player directly (used by WHO'S STARTING? selection).
  GameState setActivePlayer(int index) =>
      copyWith(activePlayerIndex: index, choosingStarter: false, gameStarted: true);

  // Apply new player list and starting life from Setup draft, then trigger
  // WHO'S STARTING? overlay.
  GameState applySetup({
    required List<Player> newPlayers,
    required int newStartingLife,
  }) {
    final solo = newPlayers.length == 1;
    // Guarantee no rotation for a solo player regardless of their prior seat.
    final resolved = solo
        ? [newPlayers[0].copyWith(seatPosition: SeatPosition.bottomEdge)]
        : newPlayers;
    return GameState(
      players: resolved.map((p) => p.copyWith(lifeTotal: newStartingLife)).toList(),
      startingLife: newStartingLife,
      activePlayerIndex: 0,
      gameStarted: solo,
      choosingStarter: !solo,
    );
  }

  // Keep the same players and colors but reset life totals and non-permanent trackers.
  GameState resetGame() {
    final solo = players.length == 1;
    return GameState(
      players: players
          .map((p) => p.copyWith(
                lifeTotal: startingLife,
                trackers: p.trackers
                    .where((t) => t.permanent)
                    .map((t) => t.reset())
                    .toList(),
                commanderDamage: {for (final id in p.commanderDamage.keys) id: 0},
              ))
          .toList(),
      startingLife: startingLife,
      gameStarted: solo,
      choosingStarter: !solo,
    );
  }
}
