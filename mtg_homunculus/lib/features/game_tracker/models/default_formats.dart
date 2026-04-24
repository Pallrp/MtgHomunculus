import '../../settings/models/format_preset.dart';

// Bundled default format presets seeded into a fresh install.
// IDs must be stable — recorded in gt.seededFormatIds to avoid re-seeding.
const List<FormatPreset> kDefaultFormats = [
  FormatPreset(id: 'commander', name: 'Commander', startingLife: 40, playerCount: 4),
  FormatPreset(id: 'standard',  name: 'Standard',  startingLife: 20, playerCount: 2),
  FormatPreset(id: 'solo',      name: 'Solo',       startingLife: 20, playerCount: 1),
];
