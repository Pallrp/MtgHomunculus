import 'tracker.dart';

// Bundled default trackers seeded into a fresh install.
// IDs must be stable — they are used to track which defaults have been seeded
// so that new entries added in future app updates are added to existing installs
// without re-adding ones the user has deleted.
// Note: commander damage is NOT in this list — it is a first-class feature
// handled separately via Player.commanderDamage, not the tracker system.
const List<Tracker> kDefaultTrackers = [
  Tracker(id: 'poison',     icon: '🐍',  name: 'Poison',      permanent: true),
  Tracker(id: 'experience', icon: '👴',  name: 'Experience',  permanent: true),
  Tracker(id: 'energy',     icon: '⚡',  name: 'Energy',      permanent: true),
  Tracker(id: 'storm',      icon: '🌩️', name: 'Storm',       permanent: false),
  Tracker(id: 'descend',    icon: '💀',  name: 'Descend',     permanent: false),
];
