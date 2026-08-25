import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtg_homunculus/features/card_lookup/data/collection_database.dart';

void main() {
  late CollectionDatabase db;

  setUp(() => db = CollectionDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<int> add(
    int listId, {
    String cardId = 'c1',
    String name = 'Swamp',
    String set = 'm21',
    String num = '267',
    int finish = VariantDefaults.finish,
    String language = VariantDefaults.language,
    int condition = VariantDefaults.condition,
    int quantity = 1,
  }) =>
      db.addCard(
        listId: listId,
        cardId: cardId,
        name: name,
        setCode: set,
        collectorNumber: num,
        finish: finish,
        language: language,
        condition: condition,
        quantity: quantity,
      );

  group('the default list', () {
    test('exists as soon as the database opens', () async {
      final all = await db.allLists();
      expect(all, hasLength(1));
      expect(all.single.isDefault, isTrue);
    });

    test('is not created twice', () async {
      await db.ensureDefaultList();
      await db.ensureDefaultList();
      expect(await db.allLists(), hasLength(1));
    });

    test('cannot be deleted — it is the scan target', () async {
      final def = await db.ensureDefaultList();
      expect(await db.deleteList(def.id), isFalse);
      expect(await db.listById(def.id), isNotNull);
    });

    test('leads the folder regardless of activity elsewhere', () async {
      final other = await db.createList('Trades');
      await add(other.id); // touches `other`, making it the most recent
      final all = await db.allLists();
      expect(all.first.isDefault, isTrue);
    });
  });

  group('the variant key', () {
    late int listId;
    setUp(() async => listId = (await db.ensureDefaultList()).id);

    test('the same variant increments rather than adding a row', () async {
      final a = await add(listId);
      final b = await add(listId);
      expect(b, a, reason: 'same row');
      expect((await db.entriesIn(listId)).single.quantity, 2);
    });

    test('a different finish is a different entry', () async {
      await add(listId);
      await add(listId, finish: Finish.foil);
      expect(await db.entriesIn(listId), hasLength(2));
    });

    test('a different language is a different entry', () async {
      await add(listId);
      await add(listId, language: 'ja');
      expect(await db.entriesIn(listId), hasLength(2));
    });

    test('a different condition is a different entry', () async {
      await add(listId);
      await add(listId, condition: Condition.heavilyPlayed);
      expect(await db.entriesIn(listId), hasLength(2));
    });

    test('the same printing in two lists is two entries', () async {
      final other = await db.createList('Trades');
      await add(listId);
      await add(other.id);
      expect(await db.entriesIn(listId), hasLength(1));
      expect(await db.entriesIn(other.id), hasLength(1));
    });

    test('quantity cannot be stored at zero', () async {
      await expectLater(
        db.into(db.entries).insert(EntriesCompanion.insert(
              listId: listId,
              cardId: 'c9',
              finish: Finish.nonfoil,
              language: 'en',
              condition: Condition.nearMint,
              quantity: 0,
              addedAt: 0,
              snapName: 'x',
              snapSetCode: 'y',
              snapCollector: '1',
            )),
        throwsA(anything),
      );
    });
  });

  group('quantity', () {
    late int listId;
    setUp(() async => listId = (await db.ensureDefaultList()).id);

    test('stepping to zero removes the row', () async {
      // The stepper's minus is how a bad scan is undone; stopping at 1 would
      // need a second, different gesture to finish the job.
      final id = await add(listId);
      await db.setQuantity(id, 0);
      expect(await db.entriesIn(listId), isEmpty);
    });

    test('setting a quantity replaces rather than adds', () async {
      final id = await add(listId, quantity: 3);
      await db.setQuantity(id, 5);
      expect((await db.entriesIn(listId)).single.quantity, 5);
    });
  });

  group('editing an entry', () {
    late int listId;
    setUp(() async => listId = (await db.ensureDefaultList()).id);

    test('changing the finish keeps one row', () async {
      final id = await add(listId);
      await db.updateEntry(id, finish: Finish.foil);
      final rows = await db.entriesIn(listId);
      expect(rows, hasLength(1));
      expect(rows.single.finish, Finish.foil);
    });

    test('editing into a variant that already exists merges them', () async {
      // Without this the UNIQUE constraint throws, on an edit whose intent —
      // "these two are the same thing" — was perfectly clear.
      final plain = await add(listId, quantity: 2);
      final foil = await add(listId, finish: Finish.foil, quantity: 3);

      final surviving = await db.updateEntry(foil, finish: Finish.nonfoil);

      final rows = await db.entriesIn(listId);
      expect(rows, hasLength(1));
      expect(rows.single.quantity, 5);
      expect(surviving, plain, reason: 'the merge target survives');
    });

    test('changing the printing carries a new snapshot', () async {
      final id = await add(listId);
      await db.updateEntry(id,
          cardId: 'c2', name: 'Island', setCode: 'lci', collectorNumber: '286');
      final row = (await db.entriesIn(listId)).single;
      expect(row.cardId, 'c2');
      expect(row.snapName, 'Island');
      expect(row.snapCollector, '286');
    });
  });

  group('cut and copy', () {
    late int source;
    late int target;
    setUp(() async {
      source = (await db.ensureDefaultList()).id;
      target = (await db.createList('Trades')).id;
    });

    test('copy leaves the source intact', () async {
      await add(source, quantity: 2);
      final ids = (await db.entriesIn(source)).map((e) => e.id);
      await db.copyTo(ids, target);
      expect(await db.entriesIn(source), hasLength(1));
      expect((await db.entriesIn(target)).single.quantity, 2);
    });

    test('cut empties the source', () async {
      await add(source);
      final ids = (await db.entriesIn(source)).map((e) => e.id).toList();
      await db.cutTo(ids, target);
      expect(await db.entriesIn(source), isEmpty);
      expect(await db.entriesIn(target), hasLength(1));
    });

    test('copying onto an existing variant merges quantities', () async {
      await add(source, quantity: 2);
      await add(target, quantity: 1);
      final ids = (await db.entriesIn(source)).map((e) => e.id);
      await db.copyTo(ids, target);
      final rows = await db.entriesIn(target);
      expect(rows, hasLength(1));
      expect(rows.single.quantity, 3);
    });

    test('copying to the same list is a no-op, not a doubling', () async {
      await add(source, quantity: 2);
      final ids = (await db.entriesIn(source)).map((e) => e.id).toList();
      await db.copyTo(ids, source);
      expect((await db.entriesIn(source)).single.quantity, 2);
    });
  });

  group('deleting a list', () {
    test('takes its entries with it', () async {
      final l = await db.createList('Temp');
      await add(l.id);
      expect(await db.deleteList(l.id), isTrue);
      final left = await db.select(db.entries).get();
      expect(left, isEmpty, reason: 'cascade must be on');
    });
  });

  group('counts', () {
    test('separate copies from unique rows', () async {
      final l = (await db.ensureDefaultList()).id;
      await add(l, quantity: 3);
      await add(l, finish: Finish.foil, quantity: 2);
      await add(l, cardId: 'c2', name: 'Island');

      final c = await db.countsFor(l);
      expect(c.copies, 6);
      expect(c.unique, 3);
    });

    test('an empty list counts zero rather than failing', () async {
      final l = (await db.ensureDefaultList()).id;
      final c = await db.countsFor(l);
      expect(c.copies, 0);
      expect(c.unique, 0);
    });

    test('all lists are counted in one query', () async {
      final a = (await db.ensureDefaultList()).id;
      final b = (await db.createList('Trades')).id;
      await add(a, quantity: 2);
      await add(b);

      final all = await db.countsForAll();
      expect(all[a]?.copies, 2);
      expect(all[b]?.copies, 1);
    });
  });
}
