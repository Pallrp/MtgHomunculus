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

  // id is included (unlike copyWith) so a serialised preset can be matched
  // against gt.seededTrackerIds across sessions.
  Map<String, dynamic> toJson() => {
    'id':        id,
    'icon':      icon,
    'name':      name,
    'value':     value,
    'permanent': permanent,
  };

  factory Tracker.fromJson(Map<String, dynamic> json) => Tracker(
    id:        json['id']        as String,
    icon:      json['icon']      as String,
    name:      json['name']      as String,
    value:     json['value']     as int? ?? 0,
    permanent: json['permanent'] as bool? ?? false,
  );
}
