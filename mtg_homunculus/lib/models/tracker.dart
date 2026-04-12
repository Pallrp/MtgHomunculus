class Tracker {
  final String icon;
  final String name;
  final int value;
  final bool permanent;
  final String? sourcePlayerId;

  const Tracker({
    required this.icon,
    required this.name,
    this.value = 0,
    this.permanent = false, // non-permanent trackers reset on [PASS]
    this.sourcePlayerId,
  });

  Tracker copyWith({
    String? icon,
    String? name,
    int? value,
    bool? permanent,
    String? sourcePlayerId,
  }) =>
      Tracker(
        icon: icon ?? this.icon,
        name: name ?? this.name,
        value: value ?? this.value,
        permanent: permanent ?? this.permanent,
        sourcePlayerId: sourcePlayerId ?? this.sourcePlayerId,
      );

  Tracker reset() => copyWith(value: 0);
}
