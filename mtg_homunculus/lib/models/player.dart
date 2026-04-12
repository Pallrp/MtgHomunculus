import 'package:flutter/material.dart';
import 'tracker.dart';

class Player {
  final Color color;
  final int lifeTotal;
  final List<Tracker> trackers;

  const Player({
    required this.color,
    required this.lifeTotal,
    this.trackers = const [],
  });

  // Factory constructor: a named constructor that returns a new instance.
  // Used when creation has logic beyond just assigning fields.
  factory Player.create({required Color color, required int startingLife}) {
    return Player(
      color: color,
      lifeTotal: startingLife,
    );
  }

  Player copyWith({
    Color? color,
    int? lifeTotal,
    List<Tracker>? trackers,
  }) =>
      Player(
        color: color ?? this.color,
        lifeTotal: lifeTotal ?? this.lifeTotal,
        trackers: trackers ?? this.trackers,
      );
}
