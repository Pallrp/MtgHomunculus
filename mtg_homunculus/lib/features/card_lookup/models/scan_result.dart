import 'rotated_card_rect.dart';
import 'scryfall_card.dart';

/// Result of processing one detected card border through the scan pipeline.
///
/// [border] is in **sensor/image coordinates** — the same space that
/// [CardDetector] produces and [CardBorderPainter] consumes.
/// The overlay widget transforms it to display coordinates for positioning
/// spinners and result chips.
sealed class ScanResult {
  /// The detected card rectangle (rotated) in sensor coordinates.
  final RotatedCardRect border;
  const ScanResult(this.border);
}

/// The pipeline identified the card and it was added to the active list.
final class MatchedResult extends ScanResult {
  final ScryfallCard card;

  /// Entry id of the created or quantity-incremented row in `collection.db`.
  ///
  /// Zero when the result was not persisted — [ScanPipeline] is usable without
  /// an `onCardAdded`, and the printing browser has nothing to update then.
  final int entryId;

  const MatchedResult(super.border, this.card, this.entryId);
}

/// The card was identified, and is the same one that was just added.
///
/// Not a failure and not shown to the user: the scan loop runs two to three
/// times a second, so a card held still in frame resolves correctly on every
/// frame. This exists as a distinct outcome rather than a silent `return` so the
/// loop can log how often it fires — a rate that suddenly drops means duplicate
/// rejection has stopped working, and a listing full of quantity-14 rows is a
/// slow way to find that out.
final class DuplicateResult extends ScanResult {
  final ScryfallCard card;

  const DuplicateResult(super.border, this.card);
}

/// The pipeline could not match the card (OCR found nothing or Scryfall
/// returned 404).  The card is **not** added to the listing.
///
/// [ocrText] is the raw OCR output (may be empty string if OCR found nothing);
/// it is pre-filled into the manual-entry dialog when the user taps this chip.
final class FailedResult extends ScanResult {
  /// Raw OCR text, or empty string if OCR produced no output.
  final String ocrText;

  const FailedResult(super.border, this.ocrText);
}
