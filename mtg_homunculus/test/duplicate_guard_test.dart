import 'package:flutter_test/flutter_test.dart';
import 'package:mtg_homunculus/features/card_lookup/data/cards_database.dart';
import 'package:mtg_homunculus/features/card_lookup/services/card_identifier.dart';
import 'package:mtg_homunculus/features/card_lookup/services/duplicate_guard.dart';

/// A fingerprint stated directly, so each test says what the *scan produced*
/// rather than reconstructing it through the identifier.
ScanFingerprint fp(String name, {Set<String>? candidates}) => ScanFingerprint(
      name: name,
      candidateNames: candidates ?? {name},
    );

Card card(String id, {String name = 'Swamp', String set = 'm21', String num = '267'}) =>
    Card(
      id: id,
      oracleId: 'oracle-1',
      name: name,
      setCode: set,
      collectorNumber: num,
      lang: 'en',
      fullArt: false,
      hasBack: false,
      imageStatus: 3,
      finishes: 1,
    );

void main() {
  late DuplicateGuard guard;
  setUp(() => guard = DuplicateGuard());

  group('an empty slot', () {
    test('nothing is a duplicate before anything has been added', () {
      expect(guard.isDuplicate(fp('Swamp')), isFalse);
    });

    test('a scan that found nothing cannot match', () {
      guard.remember(fp('Swamp'));
      expect(
        guard.isDuplicate(
          const ScanFingerprint(name: 'Swamp', candidateNames: {}),
        ),
        isFalse,
      );
    });
  });

  group('the card in view', () {
    test('is rejected for as long as it stays there', () {
      // The loop fires 2-3x/second; without this one card becomes a dozen.
      guard.remember(fp('Swamp'));
      expect(guard.isDuplicate(fp('Swamp')), isTrue);
      expect(guard.isDuplicate(fp('Swamp')), isTrue, reason: 'stays rejected');
    });

    test('is rejected however many printings the frame offered', () {
      // Nine art-identical Swamps collapse to one name. The path changes
      // between frames — hash, hashAndOcr, ocr — and the candidate ids change
      // with it; the name does not.
      guard.remember(fp('Swamp'));
      expect(guard.isDuplicate(fp('Swamp', candidates: {'Swamp'})), isTrue);
    });

    test('a different card is added', () {
      guard.remember(fp('Swamp'));
      expect(guard.isDuplicate(fp('Gruesome Slaughter')), isFalse);
    });
  });

  group('every candidate must match', () {
    test('a frame that could not separate two cards is not discarded', () {
      // "Swamp" and "Swamp Mosquito" are different cards. Discarding this frame
      // because one of them is the card just added would hide a real miss.
      guard.remember(fp('Swamp'));
      expect(
        guard.isDuplicate(fp('Swamp', candidates: {'Swamp', 'Swamp Mosquito'})),
        isFalse,
      );
    });

    test('matching is exact, never a prefix', () {
      guard.remember(fp('Swamp'));
      expect(guard.isDuplicate(fp('Swamp Mosquito')), isFalse);
    });

    test('and never a substring the other way', () {
      guard.remember(fp('Swamp Mosquito'));
      expect(guard.isDuplicate(fp('Swamp')), isFalse);
    });
  });

  group('Choose Version', () {
    test('the pick alone arms the slot, not the printings offered', () {
      // Choosing one Swamp out of nine says something about that card, not
      // about the other eight.
      final id = Identification(
        candidates: [card('s1'), card('s2')],
        via: IdentifiedVia.hash,
      );
      guard.remember(ScanFingerprint.of(id, card('s2')));
      expect(guard.lastName, 'Swamp');
    });

    test('a skip arms nothing — the guard is simply not told', () {
      // Skipping leaves the slot as it was, so the card can be retried straight
      // away. What stops the picker re-opening is the paused detection in
      // ScannerOverlay, not this class.
      guard.remember(fp('Swamp'));
      expect(guard.lastName, 'Swamp');
      expect(guard.isDuplicate(fp('Attercop')), isFalse,
          reason: 'a skipped card never reaches the slot');
    });
  });

  group('regression — re-added on every frame, 2026-08-26', () {
    test('the path changing between frames does not re-add the card', () {
      // Measured on device. One motionless Swamp, alternating between
      // hashAndOcr (1 candidate) and hash (8-12 candidates) frames. Every
      // earlier design compared something finer than the name, and the frames
      // disagreed with each other about a card that had not moved.
      guard.remember(fp('Swamp'));

      for (final frame in [
        fp('Swamp'), // hashAndOcr, 1 candidate
        fp('Swamp', candidates: {'Swamp'}), // hash, 8 candidates
        fp('Swamp', candidates: {'Swamp'}), // hash, 4 candidates
        fp('Swamp'), // hashAndOcr, 1 candidate
      ]) {
        expect(guard.isDuplicate(frame), isTrue,
            reason: 'no frame of a motionless card may re-add it');
      }
    });
  });

  group('the slot holds only the last card', () {
    test('A then B then A adds A again', () {
      // Deliberate. The user may own two copies, and undoing one row is cheaper
      // than silently dropping a real card.
      guard.remember(fp('Swamp'));
      expect(guard.isDuplicate(fp('Gruesome Slaughter')), isFalse);
      guard.remember(fp('Gruesome Slaughter'));
      expect(guard.isDuplicate(fp('Swamp')), isFalse);
    });
  });

  group('reset', () {
    test('clears the slot', () {
      guard.remember(fp('Swamp'));
      guard.reset();
      expect(guard.lastName, isNull);
      expect(guard.isDuplicate(fp('Swamp')), isFalse);
    });
  });

  group('ScanFingerprint.of', () {
    test('takes its name from the resolved row, not from OCR', () {
      final chosen = card('s5');
      final id = Identification(
        candidates: [card('s1'), chosen],
        via: IdentifiedVia.hash,
        ocrText: 'SVVAMP',
      );
      expect(ScanFingerprint.of(id, chosen).name, 'Swamp');
    });

    test('collapses reprints of one card to a single name', () {
      final id = Identification(
        candidates: [
          card('s1'),
          card('s2', set: 'lci', num: '285'),
          card('s3', set: 'iko', num: '267'),
        ],
        via: IdentifiedVia.hash,
      );
      expect(ScanFingerprint.of(id, card('s1')).candidateNames, {'Swamp'});
    });

    test('keeps two names apart when the scan could not decide', () {
      final id = Identification(
        candidates: [card('s1'), card('m1', name: 'Swamp Mosquito')],
        via: IdentifiedVia.ocr,
      );
      expect(ScanFingerprint.of(id, card('s1')).candidateNames,
          {'Swamp', 'Swamp Mosquito'});
    });
  });
}
