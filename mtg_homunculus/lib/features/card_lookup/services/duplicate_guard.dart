import '../data/cards_database.dart';
import 'card_identifier.dart';

/// Everything one scan established about which card it was.
///
/// Built from what the scan *produced*, which is why the printed fields are
/// nullable: a card identified by dHash through glare has a printing but no
/// readable collector number, and treating the matched row's number as though it
/// had been read would make the strongest signal always available.
class ScanFingerprint {
  /// The printing this scan settled on — the sole candidate, the one the user
  /// picked, or the best candidate if it was never resolved.
  final String printingId;

  /// Every printing this scan considered.
  ///
  /// Kept because the chosen one is not stable across frames. Two consecutive
  /// frames of the same physical card produce the same candidate *set* but not
  /// necessarily the same top candidate, and if the user picked the fifth entry
  /// out of Choose Version, the next frame's best candidate is the first again.
  /// Comparing sets is what stops that from reading as a different card.
  final Set<String> candidateIds;

  final String name;

  /// Read off the card, lowercase. Null when the band did not parse.
  final String? printedSetCode;
  final String? printedCollectorNumber;

  const ScanFingerprint({
    required this.printingId,
    required this.candidateIds,
    required this.name,
    this.printedSetCode,
    this.printedCollectorNumber,
  });

  /// [chosen] is the printing to record — the user's pick where there was one,
  /// otherwise the identification's own best.
  factory ScanFingerprint.of(Identification id, Card chosen) => ScanFingerprint(
        printingId: chosen.id,
        candidateIds: {chosen.id, for (final c in id.candidates) c.id},
        name: chosen.name,
        printedSetCode: id.readSetCode,
        printedCollectorNumber: id.readCollectorNumber,
      );

  /// Rank 1 — set code plus collector number, read from the card itself.
  ///
  /// Both are required. The set code is the least reliable field on a card, so
  /// this is available less often than it looks. It exists for the one thing the
  /// printing cannot do: tell two physically different cards apart when they
  /// resolved to the same candidates.
  bool get hasPrinted =>
      printedSetCode != null && printedCollectorNumber != null;

  @override
  String toString() => hasPrinted
      ? '$name [$printedSetCode $printedCollectorNumber]'
      : '$name [${candidateIds.length} candidate(s)]';
}

/// Rejects the same physical card being acted on over and over.
///
/// The scan loop fires two to three times a second, and a card sitting still in
/// frame is identified successfully every time. Without this, holding one card
/// steady for five seconds adds it a dozen times — the loop's own success is what
/// makes the guard necessary.
///
/// It also guards the one interruption. An ambiguous card that stays in frame
/// would re-open Choose Version every few hundred milliseconds, so a scan is
/// remembered when the user **skips** it too, not only when a card is added.
/// Skipping has to mean "not this one, keep scanning" rather than "ask me again
/// immediately".
///
/// **Only the immediately previous card is compared.** The window is otherwise
/// unbounded: A held for a minute stays rejected the whole time. Scanning
/// A -> B -> A does add A twice, which is deliberate — the user may own two
/// copies, and undoing one row is cheaper than silently dropping a real card.
class DuplicateGuard {
  ScanFingerprint? _last;

  ScanFingerprint? get last => _last;

  /// Whether [next] is the same card as the one last acted on.
  ///
  /// **The strongest signal available on both sides decides, and a mismatch
  /// there overrides a match on anything weaker.** Two printings of the same
  /// card are distinct and must both be added, so overlapping candidates cannot
  /// make something a duplicate when the collector numbers disagree.
  bool isDuplicate(ScanFingerprint next) {
    final prev = _last;
    if (prev == null) return false;

    // Rank 1 — printed set + collector, on both sides.
    if (prev.hasPrinted && next.hasPrinted) {
      return prev.printedSetCode == next.printedSetCode &&
          prev.printedCollectorNumber == next.printedCollectorNumber;
    }

    // Rank 2 — the printings considered.
    //
    // Overlap rather than equality: candidate lists shift by an entry or two
    // between frames as the warp moves, and requiring an exact match would let
    // a card re-add itself on the frame a candidate dropped out.
    //
    // The design also lists a rank 3, the OCR name. It is deliberately not
    // implemented: a fingerprint only exists once a scan resolved to a row, so
    // both sides always carry candidates and rank 3 can never be reached.
    // Adding it would be dead code that reads as a working safety net.
    return prev.candidateIds.intersection(next.candidateIds).isNotEmpty;
  }

  void remember(ScanFingerprint fp) => _last = fp;

  /// Forget the last card, so an identical one is acted on again.
  ///
  /// Called when the scanner stops — leaving the screen and coming back is the
  /// user saying "this is a new scan", and the second copy of a card they just
  /// scanned would otherwise vanish silently.
  void reset() => _last = null;
}
