class FormatPreset {
  final String id;        // stable, used for seeding
  final String name;
  final int startingLife;
  final int playerCount;  // suggested player count when this format is applied

  const FormatPreset({
    required this.id,
    required this.name,
    required this.startingLife,
    required this.playerCount,
  });

  FormatPreset copyWith({
    String? name,
    int?    startingLife,
    int?    playerCount,
  }) =>
      FormatPreset(
        id:           id,
        name:         name         ?? this.name,
        startingLife: startingLife ?? this.startingLife,
        playerCount:  playerCount  ?? this.playerCount,
      );

  // id included so seeding logic can match across sessions.
  Map<String, dynamic> toJson() => {
        'id':           id,
        'name':         name,
        'startingLife': startingLife,
        'playerCount':  playerCount,
      };

  factory FormatPreset.fromJson(Map<String, dynamic> json) => FormatPreset(
        id:           json['id']           as String,
        name:         json['name']         as String,
        startingLife: json['startingLife'] as int,
        // Graceful fallback: old data missing playerCount defaults to 2.
        // Any extra keys (e.g. old defaultTrackerIds) are silently ignored.
        playerCount:  json['playerCount']  as int? ?? 2,
      );
}
