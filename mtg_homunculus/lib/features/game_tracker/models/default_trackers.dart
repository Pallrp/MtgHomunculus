import 'tracker.dart';

// Bundled default trackers seeded into a fresh install.
// IDs must be stable — they are used to track which defaults have been seeded
// so that new entries added in future app updates are added to existing installs
// without re-adding ones the user has deleted.
const List<Tracker> kDefaultTrackers = [
  Tracker(
    id: 'commander_damage',
    icon: '👑',
    name: 'Commander damage',
    permanent: true,
    tracksSourcePlayer: true,
  ),
  Tracker(
    id: 'poison',
    icon: '🐍',
    name: 'Poison',
    permanent: true,
  ),
  Tracker(
    id: 'experience',
    icon: '👴',
    name: 'Experience',
    permanent: true,
  ),
  Tracker(
    id: 'energy',
    icon: '⚡',
    name: 'Energy',
    permanent: true,
  ),
  Tracker(
    id: 'storm',
    icon: '🌩️',
    name: 'Storm',
    permanent: false,
  ),
  Tracker(
    id: 'descend',
    icon: '💀',
    name: 'Descend',
    permanent: false,
  ),
];
