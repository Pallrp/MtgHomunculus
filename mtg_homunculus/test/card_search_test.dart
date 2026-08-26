import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtg_homunculus/features/card_lookup/data/cards_database.dart';

void main() {
  late CardsDatabase db;

  setUp(() async {
    db = CardsDatabase.forTesting(NativeDatabase.memory());
    for (final code in ['lci', 'xln', 'hou', '2xm']) {
      await db.into(db.sets).insert(
            CardSet(
                code: code,
                name: code.toUpperCase(),
                releasedAt: null,
                setType: null),
          );
    }
    for (final (id, name, set, num) in <(String, String, String, String)>[
      ('f-lci', 'Forest', 'lci', '285'),
      ('f-xln', 'Forest', 'xln', '277'),
      ('bolt', 'Lightning Bolt', '2xm', '129'),
      ('hod', 'Hour of Devastation', 'hou', '73'),
      ('hound', 'Ravenous Hound', 'xln', '99'),
    ]) {
      await db.into(db.cards).insert(CardsCompanion.insert(
            id: id,
            oracleId: 'o-$id',
            name: name,
            setCode: set,
            collectorNumber: num,
          ));
    }
    await db.rebuildNameIndex();
  });

  tearDown(() => db.close());

  group('the one grammar rule', () {
    test('a bare name is a name', () async {
      final p = await db.parseQuery('forest');
      expect(p.name, 'forest');
      expect(p.setCode, isNull);
    });

    test('a trailing set code filters, when a name survives without it',
        () async {
      final p = await db.parseQuery('forest lci');
      expect(p.name, 'forest');
      expect(p.setCode, 'lci');
    });

    test('a set code ALONE is a name, never a set', () async {
      // The whole point of the rule. Nobody types "hou" meaning "page through
      // 300 cards of Hour of Devastation", so that case is not supported.
      final p = await db.parseQuery('hou');
      expect(p.name, 'hou');
      expect(p.setCode, isNull);
    });

    test('a multi-word name whose last token is not a set stays a name',
        () async {
      final p = await db.parseQuery('hour of devastation');
      expect(p.name, 'hour of devastation');
      expect(p.setCode, isNull);
    });

    test('a trailing token that is not a real set code stays part of the name',
        () async {
      final p = await db.parseQuery('lightning bolt');
      expect(p.name, 'lightning bolt');
      expect(p.setCode, isNull);
    });

    test('whitespace is not a query', () async {
      expect((await db.parseQuery('   ')).name, '');
    });
  });

  group('results', () {
    test('a name returns every printing of it', () async {
      final r = await db.search('forest');
      expect(r.map((c) => c.id), containsAll(['f-lci', 'f-xln']));
    });

    test('name plus set narrows to that set', () async {
      final r = await db.search('forest lci');
      expect(r.map((c) => c.id), ['f-lci']);
    });

    test('a set code alone searches names, and finds the card', () async {
      // "hou" is a substring of "Hour of Devastation" — and must not return
      // every card in the HOU set.
      final r = await db.search('hou');
      final ids = r.map((c) => c.id).toSet();
      expect(ids, contains('hod'));
      expect(ids, isNot(contains('f-xln')),
          reason: 'a name search must not become a set listing');
    });

    test('substring matching finds a name mid-word', () async {
      final r = await db.search('hound');
      expect(r.map((c) => c.id), contains('hound'));
    });

    test('nothing matching returns nothing rather than everything', () async {
      expect(await db.search('zzzqqqxxx'), isEmpty);
    });

    test('an empty query returns nothing', () async {
      expect(await db.search('  '), isEmpty);
    });
  });

  group('printingsOf', () {
    test('returns every printing of one name', () async {
      final r = await db.printingsOf('Forest');
      expect(r.map((c) => c.id), containsAll(['f-lci', 'f-xln']));
    });

    test('an unknown name is empty, not an error', () async {
      expect(await db.printingsOf('Nonesuch'), isEmpty);
    });
  });
}
