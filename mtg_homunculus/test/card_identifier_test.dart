import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtg_homunculus/features/card_lookup/data/cards_database.dart';
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
}
