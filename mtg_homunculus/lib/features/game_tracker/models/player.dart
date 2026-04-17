import 'package:flutter/material.dart';
import 'tracker.dart';

// Where the player sits relative to the device on the table.
// Drives card rotation and grid placement.
enum SeatPosition { rightSide, leftSide, topEdge, bottomEdge }

// quarterTurns value for each seat position (used by RotatedBox)
int quarterTurnsForSeat(SeatPosition pos) => switch (pos) {
      SeatPosition.rightSide  => 3, // 90° CCW — card top faces right toward player
      SeatPosition.leftSide   => 1, // 90° CW  — card top faces left toward player
      SeatPosition.bottomEdge => 0, // no rotation — player at bottom short edge
      SeatPosition.topEdge    => 2, // 180°       — player at top short edge
    };

class Player {
  final String id;
  final Color color;
  final int lifeTotal;
  final List<Tracker> trackers;
  final SeatPosition seatPosition;
  // commanderDamage: opponentId → cumulative damage received from that opponent's commander.
  // Kept in sync by GameState when players are added or removed.
  final Map<String, int> commanderDamage;

  const Player({
    required this.id,
    required this.color,
    required this.lifeTotal,
    this.trackers = const [],
    this.seatPosition = SeatPosition.rightSide,
    this.commanderDamage = const {},
  });

  int get quarterTurns => quarterTurnsForSeat(seatPosition);

  // Generates a unique id from the current timestamp.
  static int _idSeq = 0;

  factory Player.create({
    required Color color,
    required int startingLife,
    SeatPosition seatPosition = SeatPosition.rightSide,
    Map<String, int> commanderDamage = const {},
  }) {
    return Player(
      id: '${DateTime.now().microsecondsSinceEpoch}_${_idSeq++}',
      color: color,
      lifeTotal: startingLife,
      seatPosition: seatPosition,
      commanderDamage: commanderDamage,
    );
  }

  // id intentionally excluded — a player's identity never changes.
  Player copyWith({
    Color? color,
    int? lifeTotal,
    List<Tracker>? trackers,
    SeatPosition? seatPosition,
    Map<String, int>? commanderDamage,
  }) =>
      Player(
        id: id,
        color: color ?? this.color,
        lifeTotal: lifeTotal ?? this.lifeTotal,
        trackers: trackers ?? this.trackers,
        seatPosition: seatPosition ?? this.seatPosition,
        commanderDamage: commanderDamage ?? this.commanderDamage,
      );
}
