import '../data/cards_database.dart';
import 'card_identifier.dart';

/// Everything one scan established about which card it was.
///
/// Deliberately holds no OCR-read set code or collector number. It used to, as
/// the top of a precedence ladder, and that ladder is what made a card
/// re-prompt on the frame its set code misread — see [DuplicateGuard.isDuplicate].
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

  /// The card's name as stored, not as read. Both sides of a comparison come
  /// from the card table, so this is exact rather than fuzzy.
  final String name;

  const ScanFingerprint({
    required this.printingId,
    required this.candidateIds,
    required this.name,
  });

  /// [chosen] is the printing to record — the user's pick where there was one,
  /// otherwise the identification's own best.
  factory ScanFingerprint.of(Identification id, Card chosen) => ScanFingerprint(
        printingId: chosen.id,
        candidateIds: {chosen.id, for (final c in id.candidates) c.id},
        name: chosen.name,
      );

  @override
  String toString() => '$name [${candidateIds.length} candidate(s)]';
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
/// The same applies to a card that was *added*: the frames after it resolve on
/// whichever path wins, and any of them may come back ambiguous. Being added is
/// not what stops the prompt — being recognised as the previous card is.
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
  /// **Either signal matching is enough; neither can veto the other.** The
  /// design doc ranked these, with a printed set + collector mismatch
  /// overriding a match on anything weaker. Measured on device 2026-08-26, that
  /// was wrong, and wrong in the direction that produces the worst behaviour:
  ///
  /// ```
  /// 34.16  hashAndOcr  1 candidate   Swamp   -> added
  /// 34.81  hash        9 candidates  Swamp   -> duplicate
  /// 35.20  hashAndOcr  1 candidate   Swamp   -> duplicate
  /// 35.87  ocr         4 candidates  Swamp   -> PROMPTED
  ///        iko/267, snc/267, m21/267, ltr/267
  /// ```
  ///
  /// The added printing (`m21/267`) is *in* that candidate list, so the overlap
  /// test said duplicate. The precedence rule overruled it: every candidate sat
  /// at collector `267`, meaning the set code was the field that failed, and a
  /// misread set code was allowed to veto a solid match. The set code is the
  /// least reliable thing on a card — it cannot be the tiebreaker.
  ///
  /// What that ranking existed for was two *different* printings of one card
  /// scanned back to back. That is deliberately not the workflow: same-art
  /// reprints share candidates and would be rejected regardless, and adding a
  /// second printing goes through Add Version instead.
  bool isDuplicate(ScanFingerprint next) {
    final prev = _last;
    if (prev == null) return false;

    // The printings considered.
    //
    // Overlap rather than equality: candidate lists shift by an entry or two
    // between frames as the warp moves and the path changes, and requiring an
    // exact match would let a card re-add itself on the frame a candidate
    // dropped out.
    if (prev.candidateIds.intersection(next.candidateIds).isNotEmpty) {
      return true;
    }

    // The name, as a backstop for the paths disagreeing entirely.
    //
    // dHash and the name search can return disjoint candidate sets for the same
    // physical card — one matches art, the other matches text. Both still agree
    // on what the card is *called*, and two consecutive frames naming the same
    // card are the same card. Compared as stored, since both sides come from
    // the card table rather than from OCR.
    return prev.name.isNotEmpty && prev.name == next.name;
  }

  void remember(ScanFingerprint fp) => _last = fp;

  /// Forget the last card, so an identical one is acted on again.
  ///
  /// Called when the scanner stops — leaving the screen and coming back is the
  /// user saying "this is a new scan", and the second copy of a card they just
  /// scanned would otherwise vanish silently.
  void reset() => _last = null;
}
