import 'package:flutter/material.dart';

sealed class GameEffect {
  const GameEffect();
}

// Tags one specific player (Monarch, Initiative, …).
// GameGrid pre-filters by playerId so PlayerCard never compares IDs itself.
sealed class PlayerEffect extends GameEffect {
  final String playerId;
  const PlayerEffect(this.playerId);

  // Widget shown as the badge on the player card for this effect.
  Widget cardBadge(BuildContext context);

  // Optional border color painted as a foreground ring on the player card. Null = none.
  Color? get cardOutlineColor => null;
}

// ---------------------------------------------------------------------------
// Concrete PlayerEffect types
// ---------------------------------------------------------------------------

class MonarchEffect extends PlayerEffect {
  const MonarchEffect(super.playerId);

  @override
  Widget cardBadge(BuildContext context) =>
      const Text('👑', style: TextStyle(fontSize: 18));

  @override
  Color? get cardOutlineColor => const Color(0xFFFFD700);
}

class InitiativeEffect extends PlayerEffect {
  const InitiativeEffect(super.playerId);

  @override
  Widget cardBadge(BuildContext context) => const Icon(
    Icons.flag_outlined,
    size: 18,
    color: Color(0xFF9B59B6),
  );
}
