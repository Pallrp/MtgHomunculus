import '../data/cards_database.dart';
import 'card_identifier.dart';

/// What one scan found, reduced to the only thing duplicate rejection uses.
///
/// Not a printing, not a hash, not the OCR fields — a **name**. Everything
/// narrower was tried first and each one failed the same way: the scan loop
/// re-identifies a card two to three times a second and the *path* changes
/// between frames, so any signal finer than the name disagrees with itself while
/// the card sits perfectly still. See [DuplicateGuard].
class ScanFingerprint {
  /// The name of the printing this scan settled on — the sole candidate, the
  /// one the user picked, or the best candidate if it was never resolved.
  final String name;

  /// Every distinct name among the candidates this scan considered.
  ///
  /// Usually one: reprints of a card all share its name, so nine Swamps
  /// collapse to `{'Swamp'}`. More than one means the scan genuinely could not
  /// tell two different cards apart.
  final Set<String> candidateNames;

  const ScanFingerprint({required this.name, required this.candidateNames});

  factory ScanFingerprint.of(Identification id, Card chosen) => ScanFingerprint(
        name: chosen.name,
        candidateNames: {for (final c in id.candidates) c.name},
      );

  @override
  String toString() => candidateNames.length <= 1
      ? name
      : '$name (+${candidateNames.length - 1} other name(s))';
}

/// Rejects the card that was just added, for as long as it stays in view.
///
/// The scan loop fires two to three times a second and a card sitting still is
/// identified successfully every time, so without this, holding one card steady
/// for five seconds adds it a dozen times. The loop's own success is what makes
/// the guard necessary.
///
/// **The slot holds one name.** Two earlier designs stored more and both were
/// wrong in the same direction:
///
/// - *Printed set + collector, ranked above everything else.* A misread set code
///   vetoed a correct match and re-opened Choose Version on a card already in
///   the list. The set code is the least reliable field on a card.
/// - *The set of candidate printing ids.* Better, but still finer than the
///   signal is: `hash` and `hashAndOcr` frames of one motionless card return
///   different candidate sets, so the frames disagree about a card that has not
///   moved.
///
/// The name is the one thing every path agrees on. It is taken from the resolved
/// row, not from OCR, so both sides of a comparison are exact.
///
/// **Only the immediately previous card is compared.** Scanning A -> B -> A adds
/// A twice, deliberately: the user may own two copies, and undoing one row is
/// cheaper than silently dropping a real card.
class DuplicateGuard {
  String? _lastName;

  /// The card currently occupying the slot, or null when nothing is armed.
  String? get lastName => _lastName;

  /// Whether [next] should be discarded as the card already in the slot.
  ///
  /// **Every candidate must match**, not just the best one. A frame offering
  /// `{Swamp, Swamp Mosquito}` has genuinely failed to tell two different cards
  /// apart, and discarding it because one of them happens to be the card just
  /// added would hide a real miss. Exact equality, never a prefix or substring:
  /// "Swamp" and "Swamp Mosquito" are different cards.
  bool isDuplicate(ScanFingerprint next) {
    final last = _lastName;
    if (last == null || next.candidateNames.isEmpty) return false;
    return next.candidateNames.every((n) => n == last);
  }

  /// Arm the slot with the card that was just acted on.
  ///
  /// Called when a card is added **and** when the user skips one out of Choose
  /// Version — skipping has to mean "not this one, keep scanning" rather than
  /// "ask me again in three hundred milliseconds".
  ///
  /// Only the resolved card's name is stored, never the candidates it was picked
  /// from: choosing one Swamp out of nine says something about that card, not
  /// about the other eight.
  void remember(ScanFingerprint fp) => _lastName = fp.name;

  /// Forget the slot, so an identical card is acted on again.
  ///
  /// Called when the scanner is **left** — back to the lists folder, or the app
  /// closing — and deliberately **not** when the camera merely stops. Expanding
  /// the list sheet stops the stream, and someone checking what they have
  /// collected has not told the scanner that the card in their hand is a
  /// different one.
  void reset() => _lastName = null;
}
