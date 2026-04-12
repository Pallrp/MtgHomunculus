class Tracker {
  final String id;
  final String icon;
  final String name;
  final int value;
  final bool permanent;
  final String? sourcePlayerId;

  // tracksSourcePlayer: true means the UI should prompt for an opponent when
  // this tracker is added (e.g. commander damage tracks a specific player's
  // commander). The resolved player is stored in sourcePlayerId at runtime.
  final bool tracksSourcePlayer;

  const Tracker({
    required this.id,
    required this.icon,
    required this.name,
    this.value = 0,
    this.permanent = false, // non-permanent trackers reset on [PASS]
    this.tracksSourcePlayer = false,
    this.sourcePlayerId,
  });

  // id is intentionally excluded — a tracker's identity never changes.
  Tracker copyWith({
    String? icon,
    String? name,
    int? value,
    bool? permanent,
    bool? tracksSourcePlayer,
    String? sourcePlayerId,
  }) =>
      Tracker(
        id: id,
        icon: icon ?? this.icon,
        name: name ?? this.name,
        value: value ?? this.value,
        permanent: permanent ?? this.permanent,
        tracksSourcePlayer: tracksSourcePlayer ?? this.tracksSourcePlayer,
        sourcePlayerId: sourcePlayerId ?? this.sourcePlayerId,
      );

  Tracker reset() => copyWith(value: 0);
}
