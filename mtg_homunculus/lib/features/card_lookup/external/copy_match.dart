import '../data/collection_database.dart';

/// Where a [CardLine] came from — what *Cut* takes it out of once it lands.
sealed class LineSource {
  const LineSource(this.id);
  final int id;
}

final class FromAppEntry extends LineSource {
  const FromAppEntry(super.id);
}

final class FromStaged extends LineSource {
  const FromStaged(super.id, this.direction);

  /// `add` or `remove` — the section it is staged in.
  final String direction;
}

/// A mirrored row: copied from, never cut — the mirror is Deckbox's.
final class FromMirror extends LineSource {
  const FromMirror(super.id);
}

/// One card being copied or cut (M3 step 4), whatever it came from — an app
/// list's entry, a staged change, a mirrored row — in one shape.
class CardLine {
  const CardLine({
    required this.name,
    required this.cardId,
    required this.cardRef,
    required this.anyPrinting,
    required this.finish,
    required this.languageCode,
    required this.conditionCode,
    required this.setCode,
    required this.setName,
    required this.collectorNumber,
    required this.quantity,
    required this.source,
  });

  final String name;

  /// The printing; null for a generic line — or for a mirrored row Deckbox
  /// could not be matched to one.
  final String? cardId;
  final String? cardRef;
  final bool anyPrinting;
  final int? finish;
  final String? languageCode;
  final int? conditionCode;
  final String setCode;
  final String setName;
  final String collectorNumber;
  final int quantity;
  final LineSource source;

  /// Neither a printing nor the card in any printing: a mirrored row with no
  /// printing found. It can be removed from Deckbox, not copied anywhere.
  bool get unmapped => !anyPrinting && cardId == null;

  factory CardLine.fromEntry(Entry e) => CardLine(
        name: e.snapName,
        cardId: e.cardId,
        cardRef: e.cardId,
        anyPrinting: false,
        finish: e.finish,
        languageCode: e.language,
        conditionCode: e.condition,
        setCode: e.snapSetCode,
        setName: e.snapSetName,
        collectorNumber: e.snapCollector,
        quantity: e.quantity,
        source: FromAppEntry(e.id),
      );

  /// A staged change. A removal carries its row's Deckbox edition code;
  /// an etched one (`mh2_e`) goes by its base set, as an addition is written.
  factory CardLine.fromStaged(StagedChange s) => CardLine(
        name: s.name,
        cardId: s.cardId,
        cardRef: s.cardRef,
        anyPrinting: s.anyPrinting,
        finish: s.finish,
        languageCode: s.languageCode,
        conditionCode: s.conditionCode,
        setCode: _baseSet(s.setCode),
        setName: s.setName,
        collectorNumber: s.collectorNumber,
        quantity: s.quantity,
        source: FromStaged(s.id, s.direction),
      );

  factory CardLine.fromMirror(ExternalEntry e, int count) => CardLine(
        name: e.name,
        cardId: e.cardId,
        cardRef: e.cardRef,
        anyPrinting: e.anyPrinting,
        finish: e.finish,
        languageCode: e.languageCode,
        conditionCode: e.conditionCode,
        setCode: _baseSet(e.editionCode),
        setName: e.edition,
        collectorNumber: e.cardNumber,
        quantity: count,
        source: FromMirror(e.id),
      );

  static String _baseSet(String code) => code.toLowerCase().replaceFirst(RegExp(r'_e$'), '');
}

// ---------------------------------------------------------------------------
// Copying into To remove
// ---------------------------------------------------------------------------

/// Where one copied line lands in a Deckbox list's **To remove**.
sealed class LineMatch {
  const LineMatch(this.line);
  final CardLine line;
}

/// Matched to a row: [quantity] staged from it. [excess] copies are more
/// than the row has left, and are skipped.
final class Placed extends LineMatch {
  const Placed(super.line, this.row, this.quantity, {this.chosen = false});
  final ExternalEntry row;
  final int quantity;

  /// Picked by the user, not matched automatically.
  final bool chosen;
  int get excess => line.quantity - quantity;
}

/// Several rows could be it, none exactly: the user picks, or skips.
final class Choose extends LineMatch {
  const Choose(super.line, this.rows);
  final List<ExternalEntry> rows;
}

/// Nothing staged from it, and why.
final class Unplaced extends LineMatch {
  const Unplaced(super.line, this.reason, {this.skippedByUser = false});
  final String reason;
  final bool skippedByUser;
}

/// Matching copied cards to a Deckbox list's rows — **Copy to → Remove**
/// (plan, *Cut / Copy*). **Pure**: lines and rows in, answers out.
///
/// | Match                                   | What happens            |
/// | --------------------------------------- | ----------------------- |
/// | Exact — printing and variant            | Automatic               |
/// | Only one row it could be                | Treated as exact        |
/// | Several rows, none exact                | The user chooses, or skips |
/// | Not on Deckbox                          | Skipped, counted        |
/// | More copies than Deckbox has            | What fits is staged; the rest skipped |
///
/// A printing's rows include the card's **generic** rows — any printing
/// covers it — as a scan's do. Lines are matched **in order**, each taking
/// copies from what earlier lines left, so two lines never claim the same
/// copy.
abstract final class CopyMatcher {
  /// Why a line is not placed, in the words of what is being staged.
  static const removeWords = (missing: "Deckbox doesn't have it", spent: 'All of it is already staged to remove');

  /// Marking for trade on a Tradelist (tradelist.md, step 4): the rows are the
  /// Inventory's, and what runs out is the free copies.
  static const markWords = (missing: "Not in your Inventory", spent: 'Every copy is already for trade');

  /// [left] is how many of a row's copies can still be taken — not yet staged
  /// to remove, or, marking, free and not yet staged to mark. [chosen] and
  /// [skipped] are the user's answers so far, by line index.
  static List<LineMatch> matchAll({
    required List<CardLine> lines,
    required List<ExternalEntry> rows,
    required int Function(ExternalEntry) left,
    Map<int, ExternalEntry> chosen = const {},
    Set<int> skipped = const {},
    ({String missing, String spent}) words = removeWords,
  }) {
    final taken = <int, int>{};
    int remaining(ExternalEntry e) => left(e) - (taken[e.id] ?? 0);

    LineMatch place(CardLine line, ExternalEntry row, {bool chosen = false}) {
      final n = remaining(row).clamp(0, line.quantity);
      if (n == 0) return Unplaced(line, words.spent);
      taken[row.id] = (taken[row.id] ?? 0) + n;
      return Placed(line, row, n, chosen: chosen);
    }

    return [
      for (var i = 0; i < lines.length; i++)
        if (skipped.contains(i))
          Unplaced(lines[i], 'Skipped', skippedByUser: true)
        else if (chosen[i] case final row?)
          place(lines[i], row, chosen: true)
        else
          _match(lines[i], rows, remaining, place, words),
    ];
  }

  static LineMatch _match(
    CardLine line,
    List<ExternalEntry> rows,
    int Function(ExternalEntry) remaining,
    LineMatch Function(CardLine, ExternalEntry) place,
    ({String missing, String spent}) words,
  ) {
    if (line.unmapped) return Unplaced(line, 'Not matched to a printing');
    final candidates = [
      for (final e in rows)
        if (line.anyPrinting
            ? e.name == line.name
            : (!e.anyPrinting && e.cardId == line.cardId) || (e.anyPrinting && e.name == line.name))
          e,
    ];
    if (candidates.isEmpty) return Unplaced(line, words.missing);
    final open = [for (final e in candidates) if (remaining(e) > 0) e];
    if (open.isEmpty) return Unplaced(line, words.spent);

    final exact = [for (final e in open) if (_sameVariant(line, e)) e];
    if (exact.length == 1) return place(line, exact.single);
    if (open.length == 1) return place(line, open.single);
    return Choose(line, open);
  }

  static bool _sameVariant(CardLine line, ExternalEntry e) =>
      e.anyPrinting == line.anyPrinting &&
      (line.anyPrinting ? e.name == line.name : e.cardId == line.cardId) &&
      e.finish == line.finish &&
      e.languageCode == line.languageCode &&
      e.conditionCode == line.conditionCode;

  /// Copies a matching would stage, all lines together.
  static int staged(List<LineMatch> matches) =>
      matches.whereType<Placed>().fold(0, (n, p) => n + p.quantity);

  /// Lines still waiting on the user.
  static int open(List<LineMatch> matches) => matches.whereType<Choose>().length;
}
