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
      // [dev-tool] Resolve everything the wide scan found, log it, then act only
      // on what is inside the real threshold.
      final scanned = <(Card, int)>[];
      for (final h in hashHits) {
        final c = await _db.cardById(h.id);
        if (c != null) scanned.add((c, h.distance));
      }
      if (scanned.isNotEmpty) {
        AppLogger.d('HASH-SCAN: ${scanned.map((e) =>
            '${e.$1.setCode}/${e.$1.collectorNumber}@${e.$2}').join(' ')}');
      }

      final within = [
        for (final e in scanned)
          if (e.$2 <= HashIndex.matchThreshold) e,
      ].take(12).toList();
      final cards = [for (final (c, _) in within) c];

      // Cross-check before trusting any of it. A hash match is one opinion; the
      // title band is an independent second one, and where they disagree the
      // hash is the one to doubt — it is the signal that goes wrong quietly.
      final resolvedNames = cards.isEmpty
          ? const <String>[]
          : await _resolveNames(ocr, confidentOnly: true);
      final trusted = _agreeingWithName(cards, resolvedNames);

      if (trusted.isEmpty && cards.isNotEmpty) {
        AppLogger.d('HASH-VETO: name — band says '
            '${resolvedNames.join("/")}, hash says '
            '${cards.map((c) => c.name).toSet().join("/")}');
      }

      // A lone candidate has nothing to be chosen against, so `_narrowByOcr`
      // never looks at it. This is the one gap the name cannot cover: a wrong
      // *printing* of the right card passes the name check by definition.
      final vetoed = trusted.length == 1 &&
          ocr.collectorNumber != null &&
          _collectorContradicts(
              trusted.single.collectorNumber, ocr.collectorNumber!);
      if (vetoed) {
        AppLogger.d('HASH-VETO: collector — card reads '
            '${ocr.collectorNumber}, sole match is '
            '${trusted.single.setCode}/${trusted.single.collectorNumber}');
      }

      if (trusted.isNotEmpty && !vetoed) {
        final narrowed = _narrowByOcr(trusted, ocr);
        return Identification(
          candidates: narrowed,
          via: narrowed.length < trusted.length || trusted.length < cards.length
              ? IdentifiedVia.hashAndOcr
              : IdentifiedVia.hash,
          // The distance of the nearest match actually acted on. Not the
          // nearest record found: the scan runs wider than the threshold, and
          // the cross-check can drop the closest rows.
          hashDistance: within
              .firstWhere((e) => e.$1.id == narrowed.first.id,
                  orElse: () => within.first)
              .$2,
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
      // Scanned wide, acted on narrow — see [HashIndex.diagnosticThreshold].
      // The limit must stay above the acted-on limit so filtering this list to
      // `matchThreshold` gives exactly what a plain `nearest()` would have.
      return index.nearest(
        DHash.compute(gray.data, gray.cols, gray.rows),
        threshold: HashIndex.diagnosticThreshold,
        limit: 20,
      );
    } catch (e) {
      AppLogger.w('CardIdentifier: hashing failed: $e');
      return const [];
    } finally {
      gray?.dispose();
    }
  }

  // ---------------------------------------------------------------------------
  // Cross-checking
  // ---------------------------------------------------------------------------

  /// Drop hash candidates the title band disagrees with.
  ///
  /// The name and the hash are genuinely independent — one reads text at the top
  /// of the card, the other measures art across the whole of it — so when they
  /// disagree, something is wrong. Measured 2026-08-26: of five confident wrong
  /// adds, three were a hash match for a card with a completely different name
  /// from the one printed on it, and one of those three had no readable
  /// collector number at all, so the name was the only thing that could have
  /// caught it.
  ///
  /// Returns [cards] unchanged when the band did not resolve confidently — no
  /// opinion is not the same as disagreement, and treating it as such would let
  /// glare veto correct matches.
  List<Card> _agreeingWithName(List<Card> cards, List<String> resolved) {
    if (resolved.isEmpty) return cards;
    return [
      for (final c in cards)
        if (resolved.any((n) => _namesAgree(c.name, n))) c,
    ];
  }

  /// Equal, or sharing a face.
  ///
  /// The database stores a double-faced card as `Front // Back` while a camera
  /// only ever sees one side, so plain equality would reject every DFC.
  static bool _namesAgree(String a, String b) {
    if (a == b) return true;
    final fa = a.split(' // ');
    final fb = b.split(' // ');
    return fa.any(fb.contains);
  }

  /// Whether a printed collector number contradicts a stored one.
  ///
  /// **Blocking only, and only ever consulted for a lone hash candidate.** That
  /// scoping is what makes the collector number safe to use here at all: it can
  /// cost a frame, but it has no path to *adding* anything, so a misread number
  /// cannot produce a confident wrong card the way a scoring bonus can.
  ///
  /// The set code is deliberately not consulted. Across every log it reads as
  /// garbage on most frames — `curr`, `cuir`, `clie`, `ghr`, `xlnen` — and a veto
  /// on that would block nearly everything.
  static bool _collectorContradicts(String stored, String read) {
    // Stored numbers carry suffixes and prefixes a camera never shows: `240a`,
    // `346★`, `XLN-180`. The digits are the part both sides agree on.
    final digits = RegExp(r'\d+').firstMatch(stored)?.group(0);
    if (digits == null) return false;
    return _stripZeros(digits) != _stripZeros(read);
  }

  static String _stripZeros(String s) =>
      s.replaceFirst(RegExp(r'^0+(?=\d)'), '');

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

  /// What the title band says the card is **called**, best first.
  ///
  /// Names only — no printings. The cross-check needs nothing else, and loading
  /// every printing to answer "is this a Swamp?" would mean 849 rows per frame.
  ///
  /// [confidentOnly] applies a much tighter cutoff, for callers that will treat
  /// disagreement as evidence. Garbage OCR still lands within the loose cutoff:
  /// "RERNENNc" is eight characters from plenty of real names, and the name path
  /// takes that gladly because a loose match beats nothing. A **veto** cannot,
  /// because then glare on the title band would start blocking correct matches.
  Future<List<String>> _resolveNames(_Ocr ocr, {bool confidentOnly = false}) async {
    if (ocr.name.isEmpty) return const [];
    final names = await _db.nameCandidates(ocr.name);
    if (names.isEmpty) return const [];

    final query = CardsDatabase.normaliseName(ocr.name);
    final ranked = [
      for (final n in names)
        (n, _editDistance(query, CardsDatabase.normaliseName(n), 12)),
    ]..sort((a, b) => a.$2.compareTo(b.$2));

    // Anything much worse than the best is not the same card.
    final bestDist = ranked.first.$2;
    final cutoff = confidentOnly ? 2 + query.length ~/ 6 : 12;
    if (bestDist > cutoff) return const [];

    return [
      for (final r in ranked)
        if (r.$2 <= bestDist + 2) r.$1,
    ].take(4).toList();
  }

  /// Name path: trigram retrieval, then edit-distance rerank, then the same
  /// scoring on top.
  Future<List<Card>> _byName(_Ocr ocr) async {
    final keep = await _resolveNames(ocr);
    if (keep.isEmpty) return const [];

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
