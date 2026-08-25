import 'package:camera/camera.dart';

import '../../../core/logging/app_logger.dart';
import '../data/cards_database.dart';
import '../models/rotated_card_rect.dart';
import '../models/scan_result.dart';
import '../models/scryfall_card.dart';
import 'card_identifier.dart';
import 'duplicate_guard.dart';

/// Orchestrates identification for each detected card border.
///
/// The work itself lives in [CardIdentifier]; this drives it per border and maps
/// the outcome onto [ScanResult] for the UI.
///
/// **Runs entirely against local data.** No Scryfall request is made during a
/// scan: `/cards/search` is capped at 2 requests per second and cannot back
/// something that fires twice a second, and fuzzy-name matching against a remote
/// endpoint cannot accept "this name, roughly, at this collector number" the way
/// the local index can.
class ScanPipeline {
  ScanPipeline._();

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Identify each of [borders] in [frame], calling [onResult] as each resolves.
  ///
  /// [onCardAdded] may be null, in which case matches still surface but are not
  /// persisted and [MatchedResult.listingCardId] is empty.
  static Future<void> run({
    required CameraImage frame,
    required List<RotatedCardRect> borders,
    required CardIdentifier identifier,
    required CardsDatabase db,
    required void Function(int index, ScanResult result) onResult,
    Future<String> Function(ScryfallCard card)? onCardAdded,
    Future<Card?> Function(List<Card> candidates)? onAmbiguous,
    DuplicateGuard? guard,
  }) async {
    for (var i = 0; i < borders.length; i++) {
      onResult(i, await _processOne(
        frame: frame,
        border: borders[i],
        identifier: identifier,
        db: db,
        onCardAdded: onCardAdded,
        onAmbiguous: onAmbiguous,
        guard: guard,
      ));
    }
  }

  // ---------------------------------------------------------------------------

  static Future<ScanResult> _processOne({
    required CameraImage frame,
    required RotatedCardRect border,
    required CardIdentifier identifier,
    required CardsDatabase db,
    required Future<String> Function(ScryfallCard)? onCardAdded,
    required Future<Card?> Function(List<Card>)? onAmbiguous,
    required DuplicateGuard? guard,
  }) async {
    final id = await identifier.identify(frame, border);

    AppLogger.d('ScanPipeline: ${id.via.name}'
        '${id.hashDistance == null ? "" : " d=${id.hashDistance}"}'
        '  ${id.candidates.length} candidate(s)'
        '${id.best == null ? "" : "  ${id.best!.name}"}');

    var best = id.best;
    if (best == null) return FailedResult(border, id.ocrText);

    // Duplicate check first, and specifically *before* the prompt below.
    //
    // The loop re-identifies the same card two to three times a second. If this
    // ran after the prompt, an ambiguous card left in frame would re-open Choose
    // Version every few hundred milliseconds — the user would answer it and be
    // asked again immediately, which is worse than any wrong match.
    if (guard != null && guard.isDuplicate(ScanFingerprint.of(id, best))) {
      return DuplicateResult(border, await toScryfallCard(db, best));
    }

    // Ambiguity is structural, not a failure: reprints hash identically, and a
    // name alone cannot determine a printing. Ask rather than guess — a silently
    // wrong printing is hard to notice and costs more to correct the longer a
    // session runs.
    if (id.isAmbiguous) {
      AppLogger.d('ScanPipeline: ambiguous — '
          '${id.candidates.map((c) => "${c.name} ${c.setCode}/${c.collectorNumber}").join(", ")}');
      if (onAmbiguous != null) {
        final picked = await onAmbiguous(id.candidates);
        if (picked == null) {
          // Skipped. Remembered anyway, or the card still in frame re-prompts on
          // the next frame and "skip" becomes unusable.
          guard?.remember(ScanFingerprint.of(id, best));
          return FailedResult(border, id.ocrText);
        }
        best = picked;
      }
    }

    final card = await toScryfallCard(db, best);

    // Remembered on the way to being added, not after: `onCardAdded` can throw,
    // and a card that failed to persist must not then be treated as new on every
    // subsequent frame.
    guard?.remember(ScanFingerprint.of(id, best));

    String listingCardId = '';
    if (onCardAdded != null) {
      try {
        listingCardId = await onCardAdded(card);
      } catch (e, st) {
        AppLogger.w('ScanPipeline: onCardAdded failed for "${card.name}"',
            error: e, stackTrace: st);
        return MatchedResult(border, card, '');
      }
    }
    return MatchedResult(border, card, listingCardId);
  }

  /// Adapt a local row to the model the UI already speaks.
  ///
  /// The set name lives in its own table, so this is the one lookup the mapping
  /// needs; everything else is on the card row or derivable from it.
  static Future<ScryfallCard> toScryfallCard(CardsDatabase db, Card c) async {
    final set = await (db.select(db.sets)
          ..where((s) => s.code.equals(c.setCode)))
        .getSingleOrNull();
    return ScryfallCard.fromLocal(
      id: c.id,
      name: c.name,
      setCode: c.setCode,
      setName: set?.name ?? c.setCode.toUpperCase(),
      collectorNumber: c.collectorNumber,
      finishes: c.finishes,
      imageUpdatedAt: c.imageUpdatedAt,
    );
  }
}
