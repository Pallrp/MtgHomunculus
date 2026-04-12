import 'package:flutter/material.dart';
import 'tracker.dart';

class Player {
  final String id;
  final Color color;
  final int lifeTotal;
  final List<Tracker> trackers;

  const Player({
    required this.id,
    required this.color,
    required this.lifeTotal,
    this.trackers = const [],
  });

  // Generates a unique id from the current timestamp.
  // Players are always created by a human action so microsecond precision
  // is more than sufficient to guarantee uniqueness.
  factory Player.create({required Color color, required int startingLife}) {
    return Player(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      color: color,
      lifeTotal: startingLife,
      // trackers start empty — user adds them via the manage dialog
    );
  }

  // id is intentionally excluded — a player's identity never changes.
  Player copyWith({
    Color? color,
    int? lifeTotal,
    List<Tracker>? trackers,
  }) =>
      Player(
        id: id,
        color: color ?? this.color,
        lifeTotal: lifeTotal ?? this.lifeTotal,
        trackers: trackers ?? this.trackers,
      );
}
