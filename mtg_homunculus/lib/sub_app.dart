// Sub-app identities and mount strategies.

enum SubApp { gameTracker, deckBuilder, cardLookup }

enum MountStrategy {
  /// Widget stays mounted at all times via Offstage.
  /// State survives navigation away (e.g. mid-game).
  persistent,

  /// Widget is conditionally rendered; destroyed when not active.
  /// Use for sub-apps with no in-flight state, or that load data on mount.
  onDemand,
}

extension SubAppStrategy on SubApp {
  // Exhaustive switch — compiler catches any unlisted SubApp values.
  MountStrategy get mountStrategy => switch (this) {
        SubApp.gameTracker => MountStrategy.persistent,
        SubApp.deckBuilder => MountStrategy.onDemand,
        SubApp.cardLookup  => MountStrategy.onDemand,
      };
}
