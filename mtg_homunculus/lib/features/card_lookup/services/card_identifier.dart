import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:path_provider/path_provider.dart';

import '../../../core/logging/app_logger.dart';
import '../data/cards_database.dart';
import '../data/hash_index.dart';
import '../models/rotated_card_rect.dart';
import 'card_warp.dart';
import 'dhash.dart';

/// How a card was recognised.
enum IdentifiedVia {
  /// dHash alone put exactly one card within threshold.
  hash,

  /// dHash offered several and the collector number or set code chose between
  /// them. The strongest outcome available — two independent signals agreeing.
  hashAndOcr,

  /// No hash match; the name was read and resolved against local bulk data.
  ocr,

  /// Nothing confident. Try the next frame.
  none,
}

/// What one capture yielded.
class Identification {
  /// Ranked best-first. Empty when nothing was recognised; more than one is
  /// genuinely ambiguous and belongs in Choose Version, not a guess.
  final List<Card> candidates;

  final IdentifiedVia via;

  /// Nearest hash distance, or null when there was no hash match.
  final int? hashDistance;

  /// Raw OCR, kept for Manual Add to prefill and for diagnosis.
  final String ocrText;

  /// The collector number **as read off the card**, not as stored on the matched
  /// row. Null when the band did not parse.
  ///
  /// The distinction is the whole point for duplicate rejection: every matched
  /// row has a collector number, so taking it from the database would make the
  /// strongest signal always available and rank it against itself.
  final String? readCollectorNumber;

  /// The set code as read off the card. Null when nothing set-shaped parsed.
  final String? readSetCode;

  const Identification({
    required this.candidates,
    required this.via,
    this.hashDistance,
    this.ocrText = '',
    this.readCollectorNumber,
    this.readSetCode,
  });

  static const empty =
      Identification(candidates: [], via: IdentifiedVia.none);

  bool get isIdentified => candidates.length == 1;
  bool get isAmbiguous => candidates.length > 1;
  Card? get best => candidates.isEmpty ? null : candidates.first;
}

/// Turns a detected card border into a specific printing.
///
/// ```
/// warp to 488x680
///   ├─ dHash  → index  → candidate printings
///   └─ OCR    → name, collector number, set code
///                 ↓
///   candidates narrowed by the OCR fields, which SCORE and never exclude
/// ```
///
/// The two signals are combined rather than tried in sequence. A frame that
/// hashes ambiguously may read its collector number perfectly, and a frame that
/// hashes not at all may still read its name — sequencing them throws that away.
class CardIdentifier {
  CardIdentifier(this._db, this._index);

  final CardsDatabase _db;

  /// Null until the index has been downloaded. Identification then runs on OCR
  /// alone rather than failing.
  final HashIndex? _index;

  TextRecognizer? _recognizer;

  Future<void> dispose() async {
    await _recognizer?.close();
    _recognizer = null;
  }

  // ---------------------------------------------------------------------------

  Future<Identification> identify(
    CameraImage frame,
    RotatedCardRect border,
  ) async {
    cv.Mat? card;
    try {
      card = CardWarp.fromCameraImage(frame, border.corners);
      if (card == null) return Identification.empty;
      return await identifyWarp(card);
    } catch (e, st) {
      AppLogger.w('CardIdentifier failed', error: e, stackTrace: st);
      return Identification.empty;
    } finally {
      card?.dispose();
    }
  }

  /// Identify an already-warped 488 x 680 card.
  Future<Identification> identifyWarp(cv.Mat card) async {
    final hashHits = _hashCandidates(card);
    final ocr = await _readText(card);
    return _resolve(ocr, hashHits);
  }

  /// Resolution without the camera or ML Kit, for tests.
  ///
  /// The scoring rules are where this goes wrong silently: an inverted
  /// comparison picks a plausible wrong printing rather than erroring.
  @visibleForTesting
  Future<Identification> identifyForTest({
    required String nameText,
    required String bandText,
    List<HashMatch> hashHits = const [],
  }) =>
      _resolve(_Ocr.parse(nameText, bandText), hashHits);

  Future<Identification> _resolve(_Ocr ocr, List<HashMatch> hashHits) async {
    // Hash first: it does not care that 8pt text is illegible, and it works the
    // same on full-art, saga and split layouts where text positions move.
    if (hashHits.isNotEmpty) {
      final cards = <Card>[];
      for (final h in hashHits) {
        final c = await _db.cardById(h.id);
        if (c != null) cards.add(c);
      }
      if (cards.isNotEmpty) {
        final narrowed = _narrowByOcr(cards, ocr);
        return Identification(
          candidates: narrowed,
          via: narrowed.length < cards.length
              ? IdentifiedVia.hashAndOcr
              : IdentifiedVia.hash,
          hashDistance: hashHits.first.distance,
          ocrText: ocr.raw,
          readCollectorNumber: ocr.collectorNumber,
          readSetCode: ocr.setCode,
        );
      }
    }

    // No hash match — fall back to the name.
    if (ocr.name.isNotEmpty) {
      final byName = await _byName(ocr);
      if (byName.isNotEmpty) {
        return Identification(
          candidates: byName,
          via: IdentifiedVia.ocr,
          ocrText: ocr.raw,
          readCollectorNumber: ocr.collectorNumber,
          readSetCode: ocr.setCode,
        );
      }
    }

    return Identification(
      candidates: const [],
      via: IdentifiedVia.none,
      ocrText: ocr.raw,
      readCollectorNumber: ocr.collectorNumber,
      readSetCode: ocr.setCode,
    );
  }

  // ---------------------------------------------------------------------------
  // Hash
  // ---------------------------------------------------------------------------

  List<HashMatch> _hashCandidates(cv.Mat card) {
    final index = _index;
    if (index == null) return const [];
    cv.Mat? gray;
    try {
      gray = cv.cvtColor(card, cv.COLOR_BGR2GRAY);
      return index.nearest(DHash.compute(gray.data, gray.cols, gray.rows));
    } catch (e) {
      AppLogger.w('CardIdentifier: hashing failed: $e');
      return const [];
    } finally {
      gray?.dispose();
    }
  }

  // ---------------------------------------------------------------------------
  // Narrowing
  // ---------------------------------------------------------------------------

  /// Use the OCR fields to choose between hash candidates.
  ///
  /// **Scores, never excludes.** A misread `KLN` for `XLN` costs a candidate its
  /// bonus and nothing more — if it removed rows, one wrong letter would collapse
  /// a correct set of printings to nothing.
  ///
  /// Reprints with identical art hash identically, so this is where a collector
  /// number earns its keep: it is the one field that separates them.
  List<Card> _narrowByOcr(List<Card> cards, _Ocr ocr) {
    if (cards.length == 1) return cards;
    if (ocr.collectorNumber == null && ocr.setCode == null) return cards;

    final scored = [
      for (final c in cards) (c, _score(c, ocr)),
    ]..sort((a, b) => b.$2.compareTo(a.$2));

    final top = scored.first.$2;
    if (top == 0) return cards; // nothing agreed; leave the hash order alone
    return [for (final s in scored) if (s.$2 == top) s.$1];
  }

  int _score(Card c, _Ocr ocr) {
    var score = 0;
    if (ocr.collectorNumber != null &&
        c.collectorNumber.toLowerCase() == ocr.collectorNumber) {
      score += 4;
    }
    final set = ocr.setCode;
    if (set != null) {
      final actual = c.setCode.toLowerCase();
      if (actual == set) {
        score += 3;
      } else if (_editDistance(actual, set, 1) <= 1) {
        // XLN read as KLN still counts for something — the set code is the least
        // reliable thing on the card.
        score += 1;
      }
    }
    return score;
  }

  /// Name path: trigram retrieval, then edit-distance rerank, then the same
  /// scoring on top.
  Future<List<Card>> _byName(_Ocr ocr) async {
    final names = await _db.nameCandidates(ocr.name);
    if (names.isEmpty) return const [];

    final query = CardsDatabase.normaliseName(ocr.name);
    final ranked = [
      for (final n in names)
        (n, _editDistance(query, CardsDatabase.normaliseName(n), 12)),
    ]..sort((a, b) => a.$2.compareTo(b.$2));

    // Anything much worse than the best is not the same card.
    final bestDist = ranked.first.$2;
    if (bestDist > 12) return const [];
    final keep = [
      for (final r in ranked)
        if (r.$2 <= bestDist + 2) r.$1,
    ].take(4);

    final cards = <Card>[];
    for (final n in keep) {
      cards.addAll(await (_db.select(_db.cards)
            ..where((c) => c.name.equals(n)))
          .get());
    }
    if (cards.isEmpty) return const [];
    return _narrowByOcr(cards, ocr);
  }

  // ---------------------------------------------------------------------------
  // OCR
  // ---------------------------------------------------------------------------

  Future<_Ocr> _readText(cv.Mat card) async {
    _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
    final name = await _recognise(CardWarp.nameBand(card));
    final band = await _recognise(CardWarp.collectorBand(card));
    return _Ocr.parse(name, band);
  }

  Future<String> _recognise(cv.Mat region) async {
    File? tmp;
    try {
      final (ok, jpg) = cv.imencode('.jpg', region);
      if (!ok) return '';
      final dir = await getTemporaryDirectory();
      tmp = File('${dir.path}/ocr_${DateTime.now().microsecondsSinceEpoch}.jpg');
      await tmp.writeAsBytes(jpg.toList());
      final res =
          await _recognizer!.processImage(InputImage.fromFilePath(tmp.path));
      return res.text.trim();
    } catch (e) {
      AppLogger.w('CardIdentifier: OCR failed: $e');
      return '';
    } finally {
      if (tmp != null) {
        try {
          await tmp.delete();
        } catch (_) {}
      }
    }
  }

  // ---------------------------------------------------------------------------

  /// Levenshtein with an early exit — most comparisons stop after a row or two.
  static int _editDistance(String a, String b, int cutoff) {
    if ((a.length - b.length).abs() > cutoff) return cutoff + 1;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    var curr = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      curr[0] = i;
      var rowMin = i;
      final ca = a.codeUnitAt(i - 1);
      for (var j = 1; j <= b.length; j++) {
        final cost = ca == b.codeUnitAt(j - 1) ? 0 : 1;
        var v = prev[j - 1] + cost;
        if (prev[j] + 1 < v) v = prev[j] + 1;
        if (curr[j - 1] + 1 < v) v = curr[j - 1] + 1;
        curr[j] = v;
        if (v < rowMin) rowMin = v;
      }
      if (rowMin > cutoff) return cutoff + 1;
      final t = prev;
      prev = curr;
      curr = t;
    }
    return prev[b.length];
  }
}

// ---------------------------------------------------------------------------

/// Parsed OCR from one capture.
class _Ocr {
  final String raw;
  final String name;

  /// Lowercase. Null when nothing number-shaped was read.
  final String? collectorNumber;

  /// Lowercase 3-5 letters. Null when nothing set-shaped was read.
  final String? setCode;

  const _Ocr(this.raw, this.name, this.collectorNumber, this.setCode);

  /// Pull the fields out of the two bands.
  ///
  /// Measured behaviour of the collector line (2026-08-22): the denominator is
  /// never garbled, the numerator is either right or clipped, and the set code is
  /// rarely right. Only the numerator and set code are used — the denominator is
  /// the set's printed size, which is not a clean 1..N across promo and variant
  /// runs and is deliberately not matched against.
  factory _Ocr.parse(String nameText, String bandText) {
    final name = nameText
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.length > 2, orElse: () => '');

    final num = RegExp(r'(\d{1,4})\s*/\s*\d{1,4}').firstMatch(bandText);
    final set = RegExp(r'\b([A-Za-z]{3,5})\b')
        .allMatches(bandText.split('\n').length > 1
            ? bandText.split('\n')[1]
            : bandText)
        .map((m) => m.group(1)!.toLowerCase())
        .where((s) => s != 'en')
        .firstOrNull;

    return _Ocr(
      '$nameText\n$bandText'.trim(),
      name,
      num?.group(1)?.replaceFirst(RegExp(r'^0+(?=\d)'), ''),
      set,
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
