import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtg_homunculus/features/card_lookup/data/cards_database.dart';
import 'package:mtg_homunculus/features/card_lookup/data/hash_index.dart';
import 'package:mtg_homunculus/features/card_lookup/services/card_identifier.dart';

void main() {
  late CardsDatabase db;

  setUp(() => db = CardsDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> seed(List<(String id, String name, String set, String num)> cards) async {
    for (final code in {for (final c in cards) c.$3}) {
      await db.into(db.sets).insert(
            CardSet(code: code, name: code.toUpperCase(), releasedAt: null, setType: null),
          );
    }
    for (final (id, name, set, num) in cards) {
      await db.into(db.cards).insert(CardsCompanion.insert(
            id: id,
            oracleId: 'oracle-${name.hashCode}',
            name: name,
            setCode: set,
            collectorNumber: num,
          ));
    }
    await db.rebuildNameIndex();
  }

  /// No index — exercises the OCR-only path, which is what runs before the
  /// index has been downloaded and whenever a hash finds nothing.
  CardIdentifier ocrOnly() => CardIdentifier(db, null);

  group('Identification', () {
    test('one candidate is identified, several is ambiguous', () {
      const none = Identification(candidates: [], via: IdentifiedVia.none);
      expect(none.isIdentified, isFalse);
      expect(none.isAmbiguous, isFalse);
      expect(none.best, isNull);
    });
  });

  group('name path', () {
    setUp(() => seed([
          ('a', 'Colossal Dreadmaw', 'xln', '180'),
          ('b', 'Colossal Dreadmaw', 'm21', '176'),
          ('c', 'Colossus of Akros', 'ths', '160'),
          ('d', 'Shock', 'm21', '159'),
        ]));

    test('a garbled name resolves to its printings', () async {
      final id = ocrOnly();
      final r = await id.identifyForTest(
        nameText: 'Colossai Dreadmavv',
        bandText: '',
      );
      expect(r.via, IdentifiedVia.ocr);
      expect(r.candidates.map((c) => c.id), containsAll(['a', 'b']));
      await id.dispose();
    });

    test('the collector number picks one printing out of several', () async {
      final id = ocrOnly();
      final r = await id.identifyForTest(
        nameText: 'Colossai Dreadmavv',
        bandText: '180/279 C\nXLN EN',
      );
      expect(r.candidates.single.id, 'a');
      await id.dispose();
    });

    test('a WRONG set code narrows nothing away — it only fails to add', () async {
      // The set code is the least reliable field on the card. If it excluded
      // rows, one bad letter would collapse a correct match to zero results.
      final id = ocrOnly();
      final r = await id.identifyForTest(
        nameText: 'Colossal Dreadmaw',
        bandText: '999/279 C\nZZZ EN',
      );
      expect(r.candidates.map((c) => c.id), containsAll(['a', 'b']),
          reason: 'both printings must survive a field that agreed with neither');
      await id.dispose();
    });

    test('a set code off by one letter still scores', () async {
      // KLN for XLN is the exact misread measured on device.
      final id = ocrOnly();
      final r = await id.identifyForTest(
        nameText: 'Colossal Dreadmaw',
        bandText: '\nKLN EN',
      );
      expect(r.candidates.single.id, 'a');
      await id.dispose();
    });

    test('an unreadable name yields nothing rather than a guess', () async {
      final id = ocrOnly();
      final r = await id.identifyForTest(nameText: 'zzzz qqqq xxxx', bandText: '');
      expect(r.candidates, isEmpty);
      expect(r.via, IdentifiedVia.none);
      await id.dispose();
    });

    test('empty OCR is not an error', () async {
      final id = ocrOnly();
      final r = await id.identifyForTest(nameText: '', bandText: '');
      expect(r.candidates, isEmpty);
      expect(r.via, IdentifiedVia.none);
      await id.dispose();
    });
  });

  group('field parsing', () {
    setUp(() => seed([
          ('a', 'Colossal Dreadmaw', 'xln', '180'),
          ('b', 'Colossal Dreadmaw', 'm21', '176'),
        ]));

    test('reads the numerator, and ignores the denominator', () async {
      // The denominator is the set's printed size, which is not a clean 1..N
      // across promo and variant runs. Deliberately unused.
      final id = ocrOnly();
      final r = await id.identifyForTest(
        nameText: 'Colossal Dreadmaw',
        bandText: '176/279 C\nM21 EN',
      );
      expect(r.candidates.single.id, 'b');
      await id.dispose();
    });

    test('survives the noise around the number', () async {
      final id = ocrOnly();
      final r = await id.identifyForTest(
        nameText: 'Colossal Dreadmaw',
        bandText: '180/279 C / XLN EN~SPER ESING',
      );
      expect(r.candidates.single.id, 'a');
      await id.dispose();
    });

    test('a clipped numerator simply does not match, and excludes nothing',
        () async {
      // 'D/279' and 'o/279' were both observed; the leading digits are lost.
      final id = ocrOnly();
      final r = await id.identifyForTest(
        nameText: 'Colossal Dreadmaw',
        bandText: 'D/279 C\n',
      );
      expect(r.candidates, hasLength(2));
      await id.dispose();
    });
  });

  group('the hash cross-check — five wrong adds, 2026-08-26', () {
    // Each of these is a confident wrong add that reached a real list. The
    // hash is the signal that goes wrong quietly, so it is cross-checked
    // against the title band before anything is trusted.
    setUp(() => seed([
          ('dreadmaw-xln', 'Colossal Dreadmaw', 'xln', '180'),
          ('dreadmaw-rix', 'Colossal Dreadmaw', 'rix', '125'),
          ('tainted', 'Tainted Wood', 'onc', '168'),
          ('chandra', "Chandra's Ignition", 'm3c', '209'),
          ('kabira', 'Kabira Crossroads', 'c17', '259'),
          ('swamp-m21', 'Swamp', 'm21', '267'),
          ('swamp-m12', 'Swamp', 'm12', '238'),
          ('gruesome', 'Gruesome Slaughter', 'bfz', '9'),
        ]));

    test('a hash match for a differently-named card is not trusted', () async {
      // onc/168 Tainted Wood matched at d=19 while the card in frame was a
      // Colossal Dreadmaw. The band read the name correctly the whole time.
      final id = ocrOnly();
      final r = await id.identifyForTest(
        nameText: 'Colossal Dreadmaw',
        bandText: '180/279 C\nXLN EN',
        hashHits: const [HashMatch('tainted', 19)],
      );
      expect(r.candidates.map((c) => c.id), isNot(contains('tainted')));
      expect(r.best?.id, 'dreadmaw-xln',
          reason: 'the band was right; fall through to what it says');
      await id.dispose();
    });

    test('the name catches a wrong match with no collector read at all',
        () async {
      // Kabira Crossroads. The band gave nothing number-shaped, so the name
      // was the only signal that could have caught it.
      final id = ocrOnly();
      final r = await id.identifyForTest(
        nameText: 'Colossal Dreadmaw',
        bandText: '',
        hashHits: const [HashMatch('kabira', 25)],
      );
      expect(r.candidates.map((c) => c.id), isNot(contains('kabira')));
      await id.dispose();
    });

    test("a lone match of the right card but wrong printing is vetoed",
        () async {
      // The name legitimately agrees — both are Colossal Dreadmaw — so only
      // the collector number can catch this one.
      final id = ocrOnly();
      final r = await id.identifyForTest(
        nameText: 'Colossal Dreadmaw',
        bandText: '180/279 C\nXLN EN',
        hashHits: const [HashMatch('dreadmaw-rix', 20)],
      );
      expect(r.best?.id, 'dreadmaw-xln');
      await id.dispose();
    });

    test('the M12 Swamp is vetoed by its collector number', () async {
      final id = ocrOnly();
      final r = await id.identifyForTest(
        nameText: 'Swamp',
        bandText: '267/274 C\nM21 EN',
        hashHits: const [HashMatch('swamp-m12', 20)],
      );
      expect(r.best?.id, 'swamp-m21');
      await id.dispose();
    });

    test('a lone match everything agrees with is still added', () async {
      // bfz/9 at d=26 was correct, and the band agreed. A rule that rejected
      // every uncorroborated lone match would have thrown this away.
      final id = ocrOnly();
      final r = await id.identifyForTest(
        nameText: 'Gruesome Slaughter',
        bandText: '9/274 R\nBFZ EN',
        hashHits: const [HashMatch('gruesome', 22)],
      );
      expect(r.best?.id, 'gruesome');
      expect(r.via, anyOf(IdentifiedVia.hash, IdentifiedVia.hashAndOcr));
      await id.dispose();
    });
  });

  group('what the cross-check must not do', () {
    setUp(() => seed([
          ('dreadmaw-xln', 'Colossal Dreadmaw', 'xln', '180'),
          ('swamp-m21', 'Swamp', 'm21', '267'),
          ('promo', 'Colossal Dreadmaw', 'plst', 'XLN-180'),
          ('starred', 'Colossal Dreadmaw', 'p7ed', '346a'),
        ]));

    test('an unreadable name is no opinion, not disagreement', () async {
      // Glare on the title band must not start blocking correct hash matches.
      final id = ocrOnly();
      final r = await id.identifyForTest(
        nameText: 'RERNENNc',
        bandText: '180/279 C\nXLN EN',
        hashHits: const [HashMatch('dreadmaw-xln', 12)],
      );
      expect(r.best?.id, 'dreadmaw-xln');
      await id.dispose();
    });

    test('an empty name is no opinion either', () async {
      final id = ocrOnly();
      final r = await id.identifyForTest(
        nameText: '',
        bandText: '',
        hashHits: const [HashMatch('dreadmaw-xln', 12)],
      );
      expect(r.best?.id, 'dreadmaw-xln');
      await id.dispose();
    });

    test('a prefixed collector number is not a contradiction', () async {
      // The list stores 'XLN-180'; a camera only ever shows the digits.
      final id = ocrOnly();
      final r = await id.identifyForTest(
        nameText: 'Colossal Dreadmaw',
        bandText: '180/279 C\n',
        hashHits: const [HashMatch('promo', 18)],
      );
      expect(r.best?.id, 'promo');
      await id.dispose();
    });

    test('a suffixed collector number is not a contradiction', () async {
      final id = ocrOnly();
      final r = await id.identifyForTest(
        nameText: 'Colossal Dreadmaw',
        bandText: '346/279 C\n',
        hashHits: const [HashMatch('starred', 18)],
      );
      expect(r.best?.id, 'starred');
      await id.dispose();
    });

    test('an unread collector number cannot veto', () async {
      final id = ocrOnly();
      final r = await id.identifyForTest(
        nameText: 'Colossal Dreadmaw',
        bandText: 'D/279 C\n',
        hashHits: const [HashMatch('dreadmaw-xln', 20)],
      );
      expect(r.best?.id, 'dreadmaw-xln');
      await id.dispose();
    });
  });
}
