import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtg_homunculus/features/card_lookup/data/collection_database.dart';

/// The schema-1 tables exactly as drift created them before the Deckbox
/// mirror existed — so the upgrade is tested against what a phone really has.
const _v1 = [
  'CREATE TABLE "lists" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
      '"name" TEXT NOT NULL, "description" TEXT NOT NULL DEFAULT \'\', '
      '"is_default" INTEGER NOT NULL DEFAULT 0 CHECK ("is_default" IN (0, 1)), '
      '"created_at" INTEGER NOT NULL, "updated_at" INTEGER NOT NULL)',
  'CREATE TABLE "entries" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
      '"list_id" INTEGER NOT NULL REFERENCES lists (id) ON DELETE CASCADE, '
      '"card_id" TEXT NOT NULL, "finish" INTEGER NOT NULL, "language" TEXT NOT NULL, '
      '"condition" INTEGER NOT NULL, "quantity" INTEGER NOT NULL, '
      '"added_at" INTEGER NOT NULL, "snap_name" TEXT NOT NULL, '
      '"snap_set_code" TEXT NOT NULL, "snap_set_name" TEXT NOT NULL DEFAULT \'\', '
      '"snap_collector" TEXT NOT NULL, '
      'UNIQUE ("list_id", "card_id", "finish", "language", "condition"), '
      'CHECK (quantity > 0))',
];

ExternalEntriesCompanion _row(
  int listId,
  int position,
  String name, {
  int count = 1,
  String printingId = '114480',
  String? cardId = 'scry-1',
}) =>
    ExternalEntriesCompanion.insert(
      listId: listId,
      position: position,
      count: count,
      printingId: printingId,
      condition: 'Near Mint',
      language: 'English',
      foil: '',
      rowFlags: '',
      identityKey: '$name|$printingId|Near Mint|English|',
      name: name,
      edition: 'Reality Fracture',
      editionCode: 'fra',
      cardNumber: '234',
      printingNote: '',
      anyPrinting: printingId.isEmpty,
      cardId: Value(cardId),
      cardRef: Value(cardId),
    );

void main() {
  group('upgrading from schema 1', () {
    test('keeps every app list and entry, and adds the mirror tables', () async {
      final db = CollectionDatabase.forTesting(NativeDatabase.memory(setup: (raw) {
        for (final sql in _v1) {
          raw.execute(sql);
        }
        raw.execute("INSERT INTO lists (name, is_default, created_at, updated_at) "
            "VALUES ('Scanned', 1, 1, 1), ('Trade binder', 0, 2, 2)");
        raw.execute('INSERT INTO entries (list_id, card_id, finish, language, condition, '
            'quantity, added_at, snap_name, snap_set_code, snap_collector) '
            "VALUES (2, 'c1', 1, 'en', 0, 3, 5, 'Swamp', 'm21', '267')");
        raw.execute('PRAGMA user_version = 1');
      }));
      addTearDown(db.close);

      final lists = await db.allLists();
      expect(lists.map((l) => l.name), containsAll(['Scanned', 'Trade binder']));
      expect(lists, hasLength(2), reason: 'the default list must not be re-created');
      final binder = lists.firstWhere((l) => l.name == 'Trade binder');
      final entries = await db.entriesIn(binder.id);
      expect(entries.single.quantity, 3);

      final account = await db.externalDao.upsertAccount(provider: 'deckbox', username: 'PlalBulk');
      expect(account.sessionValid, isTrue);
    });
  });

  group('the Deckbox mirror', () {
    late CollectionDatabase db;
    setUp(() => db = CollectionDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('logging in again finds the same account and marks it signed in', () async {
      final dao = db.externalDao;
      final first = await dao.upsertAccount(provider: 'deckbox', username: 'PlalBulk');
      await dao.setSessionValid(first.id, false);
      final again = await dao.upsertAccount(provider: 'deckbox', username: 'PlalBulk');
      expect(again.id, first.id);
      expect(again.sessionValid, isTrue);
    });

    test('syncLists keeps ids, follows renames, orders Inventory first', () async {
      final dao = db.externalDao;
      final a = await dao.upsertAccount(provider: 'deckbox', username: 'u');
      await dao.syncLists(a.id, [
        (remoteId: 3, kind: 'wishlist', name: 'Wishlist'),
        (remoteId: 1, kind: 'inventory', name: 'Inventory'),
        (remoteId: 2, kind: 'tradelist', name: 'Tradelist'),
      ]);
      final before = await dao.listsFor(a.id);
      expect(before.map((l) => l.kind), ['inventory', 'tradelist', 'wishlist']);

      await dao.syncLists(a.id, [(remoteId: 1, kind: 'inventory', name: 'My Inventory')]);
      final after = await dao.listsFor(a.id);
      expect(after, hasLength(3), reason: 'a list missing from the service is kept');
      expect(after.first.id, before.first.id);
      expect(after.first.name, 'My Inventory');
    });

    test('replaceMirror swaps the rows wholesale and clears a pull error', () async {
      final dao = db.externalDao;
      final a = await dao.upsertAccount(provider: 'deckbox', username: 'u');
      await dao.syncLists(a.id, [(remoteId: 1, kind: 'inventory', name: 'Inventory')]);
      final list = (await dao.listsFor(a.id)).single;

      await dao.replaceMirror(list.id, [_row(list.id, 0, 'A'), _row(list.id, 1, 'B')], pulledAt: 100);
      await dao.markStale(list.id);
      await dao.recordPullError(list.id, 'boom');

      await dao.replaceMirror(
        list.id,
        [_row(list.id, 0, 'C', count: 2), _row(list.id, 1, 'Gisela', printingId: '', cardId: null)],
        pulledAt: 200,
      );

      final rows = await dao.watchEntries(list.id).first;
      expect(rows.map((r) => r.name), ['C', 'Gisela']);
      expect(rows.last.anyPrinting, isTrue);
      expect(rows.last.cardId, isNull);

      final pulled = (await dao.listById(list.id))!;
      expect(pulled.lastPulledAt, 200);
      expect(pulled.stale, isFalse);
      expect(pulled.lastPullError, isNull);

      final counts = await dao.watchCounts().first;
      expect(counts[list.id], (copies: 3, forTrade: 0, unique: 2));
    });

    test('a failed replace leaves the previous mirror untouched', () async {
      final dao = db.externalDao;
      final a = await dao.upsertAccount(provider: 'deckbox', username: 'u');
      await dao.syncLists(a.id, [(remoteId: 1, kind: 'inventory', name: 'Inventory')]);
      final list = (await dao.listsFor(a.id)).single;
      await dao.replaceMirror(list.id, [_row(list.id, 0, 'Keep me')], pulledAt: 100);

      // A row pointing at a list that does not exist breaks the transaction.
      await expectLater(
        dao.replaceMirror(list.id, [_row(list.id, 0, 'New'), _row(9999, 1, 'Orphan')], pulledAt: 200),
        throwsA(anything),
      );
      final rows = await dao.watchEntries(list.id).first;
      expect(rows.map((r) => r.name), ['Keep me']);
      expect((await dao.listById(list.id))!.lastPulledAt, 100);
    });

    test('removing an account takes its lists and mirror with it, nothing else', () async {
      final dao = db.externalDao;
      final gone = await dao.upsertAccount(provider: 'deckbox', username: 'gone');
      final kept = await dao.upsertAccount(provider: 'deckbox', username: 'kept');
      await dao.syncLists(gone.id, [(remoteId: 1, kind: 'inventory', name: 'Inventory')]);
      await dao.syncLists(kept.id, [(remoteId: 2, kind: 'inventory', name: 'Inventory')]);
      final goneList = (await dao.listsFor(gone.id)).single;
      await dao.replaceMirror(goneList.id, [_row(goneList.id, 0, 'A')], pulledAt: 1);

      await dao.removeAccount(gone.id);

      expect(await dao.listsFor(gone.id), isEmpty);
      expect(await dao.watchEntries(goneList.id).first, isEmpty);
      expect(await dao.listsFor(kept.id), hasLength(1));
      expect(await db.allLists(), hasLength(1), reason: 'app lists are not touched');
    });
  });
}
