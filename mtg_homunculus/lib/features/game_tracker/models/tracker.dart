class Tracker {
  final String id;
  final String icon;
  final String name;
  final int value;
  final bool permanent;

  const Tracker({
    required this.id,
    required this.icon,
    required this.name,
    this.value = 0,
    this.permanent = false, // non-permanent trackers reset on pass turn
  });

  // id is intentionally excluded — a tracker's identity never changes.
  Tracker copyWith({
    String? icon,
    String? name,
    int? value,
    bool? permanent,
  }) =>
      Tracker(
        id: id,
        icon: icon ?? this.icon,
        name: name ?? this.name,
        value: value ?? this.value,
        permanent: permanent ?? this.permanent,
      );

  Tracker reset() => copyWith(value: 0);
}
