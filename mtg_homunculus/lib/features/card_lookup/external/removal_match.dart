import '../data/cards_database.dart' show Card;
import '../data/collection_database.dart';
import '../services/card_identifier.dart' show Identification;

/// What a card scanned — or picked — into **To remove** comes to.
sealed class RemovalMatch {
  const RemovalMatch();
}

/// One row it can only be: staged without asking.
final class StageRow extends RemovalMatch {
  const StageRow(this.row);
  final ExternalEntry row;
}

/// Several rows it could be: the which-copy sheet asks.
final class AskRows extends RemovalMatch {
  const AskRows(this.rows);
  final List<ExternalEntry> rows;
}

/// Not on this list — or, its printing read for certain, not in that printing.
final class NotOnList extends RemovalMatch {
  const NotOnList(this.name);
  final String name;
}

/// On the list, but every copy it could be is already staged to remove.
final class AllStaged extends RemovalMatch {
  const AllStaged(this.name);
  final String name;
}

/// Which mirrored rows a scan into **To remove** can stand for (decided
/// 2026-10-16). **Pure** — rows in, answer out — so every case is tested.
///
/// The choice is always between **Deckbox rows**, never printings: Choose
/// Version never opens for a removal. How far it narrows depends on how much
/// the scan is sure of:
///
/// | The scan knows        | Offered                                              |
/// | --------------------- | ---------------------------------------------------- |
/// | the printing (read)   | that printing's rows and the card's generic rows; no row of that printing → the generic rows only; none either → *not on this list* |
/// | the card, not printing| every row of the card                                |
/// | only the image        | every row of every card it guessed — always asked    |
///
/// Rows whose every copy is already staged drop out first. **One left is
/// staged**, unless the scan was unsure even of the card.
abstract final class RemovalMatcher {
  /// [rows] are the list's mirrored rows holding copies; [left] is how many of
  /// a row's copies are not yet staged to remove; [candidates] the scan's
  /// guesses, best first.
  static RemovalMatch resolve({
    required List<ExternalEntry> rows,
    required int Function(ExternalEntry) left,
    required List<Card> candidates,
    required bool printingKnown,
  }) {
    final names = {for (final c in candidates) c.name};
    final ofCard = [for (final e in rows) if (names.contains(e.name)) e];
    if (ofCard.isEmpty) return NotOnList(candidates.first.name);

    if (printingKnown) {
      final c = candidates.first;
      final exact = [for (final e in ofCard) if (!e.anyPrinting && e.cardId == c.id) e];
      final generic = [for (final e in ofCard) if (e.anyPrinting) e];
      // Read for certain as another printing: the list's other printings are
      // not it. Only a generic row — any printing — can be.
      final pool = exact.isEmpty ? generic : [...exact, ...generic];
      if (pool.isEmpty) return NotOnList(c.name);
      return _choose(pool, left, mustAsk: false);
    }
    return _choose(ofCard, left, mustAsk: names.length > 1);
  }

  static RemovalMatch _choose(
    List<ExternalEntry> pool,
    int Function(ExternalEntry) left, {
    required bool mustAsk,
  }) {
    final open = [for (final e in pool) if (left(e) > 0) e];
    if (open.isEmpty) return AllStaged(pool.first.name);
    if (open.length == 1 && !mustAsk) return StageRow(open.single);
    return AskRows(open);
  }

  /// Whether the scan read its printing off the card: one candidate, and the
  /// set code or collector number in its text band agrees with it. A lone
  /// hash match does not count — reprints share art.
  static bool printingRead(Identification id) {
    if (id.candidates.length != 1) return false;
    final c = id.candidates.single;
    final set = id.readSetCode?.toLowerCase();
    final number = id.readCollectorNumber;
    return (set != null && set == c.setCode.toLowerCase()) ||
        (number != null && _sameNumber(number, c.collectorNumber));
  }

  static bool _sameNumber(String read, String stored) {
    String norm(String s) => s.toLowerCase().replaceFirst(RegExp(r'^0+(?=.)'), '');
    return norm(read) == norm(stored);
  }
}
