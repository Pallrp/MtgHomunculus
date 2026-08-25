import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtg_homunculus/features/card_lookup/data/cards_database.dart';

void main() {
  late CardsDatabase db;

  setUp(() {
    db = CardsDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  Future<void> seed(List<(String name, String set, String num)> cards) async {
    final sets = {for (final c in cards) c.$2};
    for (final code in sets) {
      await db.into(db.sets).insert(
            CardSet(code: code, name: code.toUpperCase(), releasedAt: null, setType: null),
          );
    }
    for (var i = 0; i < cards.length; i++) {
      final (name, set, num) = cards[i];
      await db.into(db.cards).insert(
            CardsCompanion.insert(
              id: 'id-$i',
              oracleId: 'oracle-${name.hashCode}',
              name: name,
              setCode: set,
              collectorNumber: num,
            ),
          );
    }
  }

  group('schema', () {
    test('the trigram FTS table exists — the design depends on it', () async {
      final rows = await db
          .customSelect("SELECT sql FROM sqlite_master WHERE name='card_names_fts'")
          .get();
      expect(rows, isNotEmpty);
      expect(rows.first.read<String>('sql'), contains("tokenize='trigram'"));
    });

    test('foreign keys are enforced', () async {
      await expectLater(
        db.into(db.cards).insert(CardsCompanion.insert(
              id: 'x',
              oracleId: 'o',
              name: 'Nonexistent Set Card',
              setCode: 'nope',
              collectorNumber: '1',
            )),
        throwsA(anything),
      );
    });
  });

  group('meta', () {
    test('round-trips and overwrites', () async {
      await db.setMeta(MetaKeys.bulkEtag, '"abc"');
      expect(await db.metaValue(MetaKeys.bulkEtag), '"abc"');
      await db.setMeta(MetaKeys.bulkEtag, '"def"');
      expect(await db.metaValue(MetaKeys.bulkEtag), '"def"');
    });

    test('missing key is null, not an error', () async {
      expect(await db.metaValue('never_set'), isNull);
    });
  });

  group('name normalisation', () {
    test('strips punctuation and case, keeps single spaces', () {
      expect(CardsDatabase.normaliseName("Thalia, Guardian of Thraben"),
          'thalia guardian of thraben');
      expect(CardsDatabase.normaliseName('  Fire // Ice  '), 'fire  ice');
      expect(CardsDatabase.normaliseName('Sol Ring'), 'sol ring');
    });
  });

  group('name index', () {
    test('indexes unique names, not card rows', () async {
      await seed([
        ('Forest', 'xln', '1'),
        ('Forest', 'lci', '2'),
        ('Forest', 'neo', '3'),
        ('Colossal Dreadmaw', 'xln', '180'),
      ]);
      await db.rebuildNameIndex();

      final rows =
          await db.customSelect('SELECT COUNT(*) c FROM card_names_fts').get();
      expect(rows.first.read<int>('c'), 2,
          reason: 'three Forest printings must index as one name');
    });

    test('finds a garbled name', () async {
      await seed([
        ('Colossal Dreadmaw', 'xln', '180'),
        ('Colossus of Akros', 'ths', '160'),
        ('Shock', 'm21', '159'),
      ]);
      await db.rebuildNameIndex();

      final got = await db.nameCandidates('colossai dreadmavv');
      expect(got, isNotEmpty);
      expect(got.first, 'Colossal Dreadmaw');
    });

    test('returns the original name, not the normalised form', () async {
      await seed([('Thalia, Guardian of Thraben', 'isd', '20')]);
      await db.rebuildNameIndex();

      // Query is normalised; the punctuation in the stored name must survive.
      final got = await db.nameCandidates('thalio guordion of thrahen');
      expect(got.single, 'Thalia, Guardian of Thraben');
    });

    test('punctuation in the stored name does not block a match', () async {
      await seed([('Jace, the Mind Sculptor', 'wwk', '31')]);
      await db.rebuildNameIndex();
      expect(await db.nameCandidates('jace the mind sculptor'), isNotEmpty);
    });

    test('a query too short for a trigram returns empty, not an error', () async {
      await seed([('Shock', 'm21', '159')]);
      await db.rebuildNameIndex();
      expect(await db.nameCandidates('ab'), isEmpty);
    });

    test('addNewNames adds only names not already indexed', () async {
      await seed([('Forest', 'xln', '1')]);
      await db.rebuildNameIndex();

      await db.into(db.cards).insert(CardsCompanion.insert(
            id: 'new-1',
            oracleId: 'o2',
            name: 'Mountain',
            setCode: 'xln',
            collectorNumber: '2',
          ));
      await db.into(db.cards).insert(CardsCompanion.insert(
            id: 'new-2',
            oracleId: 'o1',
            name: 'Forest', // alternate printing — must not duplicate
            setCode: 'xln',
            collectorNumber: '3',
          ));
      await db.addNewNames();

      final rows =
          await db.customSelect('SELECT COUNT(*) c FROM card_names_fts').get();
      expect(rows.first.read<int>('c'), 2);
    });

    test('rebuild is idempotent', () async {
      await seed([('Forest', 'xln', '1'), ('Shock', 'm21', '159')]);
      await db.rebuildNameIndex();
      await db.rebuildNameIndex();
      final rows =
          await db.customSelect('SELECT COUNT(*) c FROM card_names_fts').get();
      expect(rows.first.read<int>('c'), 2);
    });
  });

  group('lookup by name', () {
    test('an FTS hit resolves to every printing', () async {
      await seed([
        ('Forest', 'xln', '1'),
        ('Forest', 'lci', '2'),
        ('Shock', 'm21', '159'),
      ]);
      await db.rebuildNameIndex();

      final name = (await db.nameCandidates('forest')).first;
      final printings =
          await (db.select(db.cards)..where((c) => c.name.equals(name))).get();
      expect(printings, hasLength(2));
      expect(printings.map((p) => p.setCode), containsAll(['xln', 'lci']));
    });
  });
}
