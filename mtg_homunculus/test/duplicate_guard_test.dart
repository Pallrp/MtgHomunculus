import 'package:flutter_test/flutter_test.dart';
import 'package:mtg_homunculus/features/card_lookup/data/cards_database.dart';
import 'package:mtg_homunculus/features/card_lookup/services/card_identifier.dart';
import 'package:mtg_homunculus/features/card_lookup/services/duplicate_guard.dart';

/// A fingerprint stated directly, so each test says what the *scan produced*
/// rather than reconstructing it through the identifier.
ScanFingerprint fp(
  String printingId, {
  String name = 'Swamp',
  Set<String>? candidates,
  String? set,
  String? number,
}) =>
    ScanFingerprint(
      printingId: printingId,
      candidateIds: candidates ?? {printingId},
      name: name,
      printedSetCode: set,
      printedCollectorNumber: number,
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

  group('first scan', () {
    test('nothing is a duplicate before anything has been added', () {
      expect(guard.isDuplicate(fp('a')), isFalse);
    });
  });

  group('rank 2 — the printings considered', () {
    test('the same card held in frame is rejected after the first add', () {
      // The loop fires 2-3x/second; without this one card becomes a dozen.
      guard.remember(fp('a'));
      expect(guard.isDuplicate(fp('a')), isTrue);
      expect(guard.isDuplicate(fp('a')), isTrue, reason: 'stays rejected');
    });

    test('a different card is added', () {
      guard.remember(fp('a'));
      expect(guard.isDuplicate(fp('b', name: 'Island')), isFalse);
    });

    test('the pick from Choose Version is not re-prompted next frame', () {
      // The regression this exists for. Nine identical-art Swamps: the user
      // picks the fifth, and the next frame's best candidate is the first
      // again. Comparing only the chosen printing would call that a new card
      // and re-open the picker every few hundred milliseconds.
      final all = {'s1', 's2', 's3', 's4', 's5'};
      guard.remember(fp('s5', candidates: all));
      expect(guard.isDuplicate(fp('s1', candidates: all)), isTrue);
    });

    test('a candidate dropping out between frames is still the same card', () {
      guard.remember(fp('s1', candidates: {'s1', 's2', 's3'}));
      expect(guard.isDuplicate(fp('s2', candidates: {'s2', 's3'})), isTrue);
    });

    test('skipping is remembered, so the picker does not reopen', () {
      // "Skip" has to mean "keep scanning", not "ask me again immediately".
      guard.remember(fp('s1', candidates: {'s1', 's2'}));
      expect(guard.isDuplicate(fp('s1', candidates: {'s1', 's2'})), isTrue);
    });
  });

  group('rank 1 — printed set and collector number', () {
    test('two printings of one card are distinct, despite shared candidates', () {
      // Rank 1 must override a rank-2 match: same art, same candidate list,
      // different physical cards. Rank 2 alone would drop the second.
      final art = {'x', 'y'};
      guard.remember(fp('x', candidates: art, set: 'lci', number: '231'));
      expect(
        guard.isDuplicate(fp('y', candidates: art, set: 'lci', number: '232')),
        isFalse,
      );
    });

    test('the same printed number is a duplicate', () {
      guard.remember(fp('x', set: 'lci', number: '231'));
      expect(guard.isDuplicate(fp('x', set: 'lci', number: '231')), isTrue);
    });

    test('a different set with the same number is distinct', () {
      guard.remember(fp('x', candidates: {'x', 'y'}, set: 'lci', number: '231'));
      expect(
        guard.isDuplicate(fp('y', candidates: {'x', 'y'}, set: 'mh3', number: '231')),
        isFalse,
      );
    });

    test('rank 1 needs both sides — an unread band falls back to rank 2', () {
      // Glare kills OCR on one frame but dHash still matches. That frame must
      // not read as a new card just because its band did not parse.
      guard.remember(fp('x', set: 'lci', number: '231'));
      expect(guard.isDuplicate(fp('x')), isTrue);
    });

    test('a half-read band does not count as rank 1', () {
      guard.remember(fp('x', candidates: {'x', 'y'}, set: 'lci', number: '231'));
      // Number read, set missing → not rank 1 → rank 2 says duplicate.
      expect(
        guard.isDuplicate(fp('y', candidates: {'x', 'y'}, number: '232')),
        isTrue,
      );
    });
  });

  group('reset', () {
    test('a second copy scanned after leaving the camera is added', () {
      guard.remember(fp('a'));
      guard.reset();
      expect(guard.isDuplicate(fp('a')), isFalse);
    });
  });

  group('ScanFingerprint.of', () {
    test('records the user pick plus every candidate considered', () {
      final chosen = card('s5');
      final id = Identification(
        candidates: [card('s1'), card('s2'), chosen],
        via: IdentifiedVia.hash,
        readSetCode: 'm21',
        readCollectorNumber: '267',
      );
      final f = ScanFingerprint.of(id, chosen);
      expect(f.printingId, 's5');
      expect(f.candidateIds, {'s1', 's2', 's5'});
      expect(f.hasPrinted, isTrue);
    });

    test('takes the printed fields from OCR, never from the matched row', () {
      // The row always has a collector number. If this read it from there,
      // rank 1 would always be available and would rank against itself.
      final chosen = card('s5', set: 'm21', num: '267');
      final id = Identification(
        candidates: [chosen],
        via: IdentifiedVia.hash,
      );
      final f = ScanFingerprint.of(id, chosen);
      expect(f.hasPrinted, isFalse);
      expect(f.printedCollectorNumber, isNull);
    });
  });
}
