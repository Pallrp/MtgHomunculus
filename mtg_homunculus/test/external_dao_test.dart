import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtg_homunculus/features/card_lookup/data/collection_database.dart';
import 'package:mtg_homunculus/features/card_lookup/external/external_dao.dart';
import 'package:mtg_homunculus/features/card_lookup/models/deckbox_prefs.dart';

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

  test('upgrading from schema 3 drops the Tradelist rows, keeps the rest, adds forTrade', () async {
    final file = File('${Directory.systemTemp.createTempSync('m3').path}/collection.db');
    var db = CollectionDatabase.forTesting(NativeDatabase(file));
    final dao = db.externalDao;
    final a = await dao.upsertAccount(provider: 'deckbox', username: 'u');
    await dao.syncLists(a.id, [
      (remoteId: 1, kind: 'inventory', name: 'Inventory'),
      (remoteId: 2, kind: 'tradelist', name: 'Tradelist'),
    ]);
    final [inv, trade] = await dao.listsFor(a.id);
    await dao.replaceMirror(inv.id, [_row(inv.id, 0, 'Bolt')], pulledAt: 1);
    await dao.replaceMirror(trade.id, [_row(trade.id, 0, 'Bolt')], pulledAt: 1);
    await dao.stageRemoval(list: inv, row: (await dao.watchEntries(inv.id).first).single);
    // Back to what a schema-3 phone has.
    await db.customStatement('ALTER TABLE staged_changes DROP COLUMN for_trade');
    await db.customStatement('PRAGMA user_version = 3');
    await db.close();

    db = CollectionDatabase.forTesting(NativeDatabase(file));
    addTearDown(db.close);
    expect(await db.externalDao.watchEntries(trade.id).first, isEmpty);
    expect(await db.externalDao.watchEntries(inv.id).first, hasLength(1));
    final staged = (await db.externalDao.stagedFor(inv.id)).single;
    expect(staged.forTrade, isFalse);
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
      expect(counts[list.id], (copies: 3, forTrade: 0, unique: 2, tradeUnique: 0));
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

    group('staging', () {
      late ExternalList inv;
      Future<ExternalEntry> mirrorRow(String name) async =>
          (await db.externalDao.watchEntries(inv.id).first).firstWhere((e) => e.name == name);

      setUp(() async {
        final dao = db.externalDao;
        final a = await dao.upsertAccount(provider: 'deckbox', username: 'u');
        await dao.syncLists(a.id, [(remoteId: 1, kind: 'inventory', name: 'Inventory')]);
        inv = (await dao.listsFor(a.id)).single;
        await dao.replaceMirror(inv.id, [_row(inv.id, 0, 'Bolt', count: 3), _row(inv.id, 1, 'Ring')], pulledAt: 1);
      });

      test('a removal is capped at what the row holds, less what is staged', () async {
        final dao = db.externalDao;
        final bolt = await mirrorRow('Bolt');
        expect(await dao.stageRemoval(list: inv, row: bolt, quantity: 2), 2);
        expect(await dao.stageRemoval(list: inv, row: bolt, quantity: 5), 1, reason: 'only 1 left to give');
        expect(await dao.stageRemoval(list: inv, row: bolt), 0);
        final staged = await dao.stagedFor(inv.id);
        expect(staged.single.quantity, 3);
        expect(staged.single.identityKey, bolt.identityKey);
      });

      test('staging the same addition again adds up', () async {
        final dao = db.externalDao;
        Future<void> addBolt() => dao.stageAddition(
              listId: inv.id,
              name: 'Bolt',
              cardId: 'scry-bolt',
              cardRef: 'scry-bolt',
              anyPrinting: false,
              finish: 1,
              languageCode: 'en',
              conditionCode: 0,
            );
        await addBolt();
        await addBolt();
        expect((await dao.stagedFor(inv.id)).single.quantity, 2);
      });

      test('a pull flags removals it can no longer satisfy, and clears them again', () async {
        final dao = db.externalDao;
        await dao.stageRemoval(list: inv, row: await mirrorRow('Bolt'), quantity: 3);
        await dao.stageRemoval(list: inv, row: await mirrorRow('Ring'));

        // Bolt drops to 1 on Deckbox; Ring disappears.
        await dao.replaceMirror(inv.id, [_row(inv.id, 0, 'Bolt', count: 1)], pulledAt: 2);
        await dao.revalidate(inv);
        var flags = {for (final s in await dao.stagedFor(inv.id)) s.name: s.flag};
        expect(flags, {'Bolt': 'short:1', 'Ring': 'gone'});

        // Both come back.
        await dao.replaceMirror(inv.id, [_row(inv.id, 0, 'Bolt', count: 3), _row(inv.id, 1, 'Ring')], pulledAt: 3);
        await dao.revalidate(inv);
        flags = {for (final s in await dao.stagedFor(inv.id)) s.name: s.flag};
        expect(flags, {'Bolt': null, 'Ring': null});
      });

      group('editing a staged addition', () {
        Future<int> addBolt({int condition = 0}) => db.externalDao.stageAddition(
              listId: inv.id,
              name: 'Bolt',
              cardId: 'scry-bolt',
              cardRef: 'scry-bolt',
              anyPrinting: false,
              finish: 1,
              languageCode: 'en',
              conditionCode: condition,
            );

        test('a chip edit changes it in place and clears its last error', () async {
          final dao = db.externalDao;
          final id = await addBolt();
          await dao.recordStagedError(id, 'Deckbox refused this row');
          expect(await dao.updateStagedAddition(id, conditionCode: const Value(2)), id);
          final s = (await dao.stagedFor(inv.id)).single;
          expect(s.conditionCode, 2);
          expect(s.lastError, isNull);
          expect(s.stageKey, contains('|2'));
        });

        test('an edit that makes it another staged addition merges the two', () async {
          final dao = db.externalDao;
          final played = await addBolt(condition: 2);
          await dao.setStagedQuantity(played, 3);
          final nm = await addBolt();
          expect(await dao.updateStagedAddition(nm, conditionCode: const Value(2)), played);
          final s = (await dao.stagedFor(inv.id)).single;
          expect(s.id, played);
          expect(s.quantity, 4);
        });

        test('Change Version to Any printing keeps the card as its reference', () async {
          final dao = db.externalDao;
          final id = await addBolt();
          await dao.updateStagedAddition(
            id,
            version: (
              name: 'Bolt',
              cardId: null,
              cardRef: 'scry-bolt',
              anyPrinting: true,
              setCode: '',
              setName: '',
              collectorNumber: '',
            ),
          );
          final s = (await dao.stagedFor(inv.id)).single;
          expect(s.anyPrinting, isTrue);
          expect(s.cardId, isNull);
          expect(s.cardRef, 'scry-bolt');
          expect(s.stageKey, startsWith('any:Bolt'));
        });
      });

      test('an Inventory addition takes Also up for trade; an explicit flag wins; edits keep it', () async {
        final dao = db.externalDao;
        Future<StagedChange> stage({bool? forTrade, String id = 'scry-x'}) async {
          final staged = await dao.stageAddition(
            listId: inv.id,
            name: 'X',
            cardId: id,
            cardRef: id,
            anyPrinting: false,
            finish: 1,
            languageCode: 'en',
            conditionCode: 0,
            forTrade: forTrade,
          );
          return (await dao.stagedById(staged))!;
        }

        DeckboxPrefs.alsoForTrade.value = true;
        final on = await stage();
        expect(on.forTrade, isTrue);
        DeckboxPrefs.alsoForTrade.value = false;
        expect((await stage(id: 'scry-y')).forTrade, isFalse);
        expect((await stage(id: 'scry-z', forTrade: true)).forTrade, isTrue);

        await dao.setForTrade(on.id, false);
        await dao.updateStagedAddition(on.id, conditionCode: const Value(2));
        expect((await dao.stagedById(on.id))!.forTrade, isFalse, reason: 'a chip edit keeps the flag');
        DeckboxPrefs.alsoForTrade.value = true;
      });

      test('a pull never touches staged additions', () async {
        final dao = db.externalDao;
        await dao.stageAddition(
          listId: inv.id,
          name: 'New card',
          cardId: 'scry-new',
          cardRef: 'scry-new',
          anyPrinting: false,
          finish: 1,
          languageCode: 'en',
          conditionCode: 0,
        );
        await dao.replaceMirror(inv.id, const [], pulledAt: 2);
        await dao.revalidate(inv);
        final s = (await dao.stagedFor(inv.id)).single;
        expect(s.flag, isNull);
        expect(s.quantity, 1);
      });
    });

    group('one mirror for an Inventory and its Tradelist (schema 4)', () {
      late ExternalList inv, trade, wish;
      setUp(() async {
        final dao = db.externalDao;
        final a = await dao.upsertAccount(provider: 'deckbox', username: 'u');
        await dao.syncLists(a.id, [
          (remoteId: 1, kind: 'inventory', name: 'Inventory'),
          (remoteId: 2, kind: 'tradelist', name: 'Tradelist'),
          (remoteId: 3, kind: 'wishlist', name: 'Wishlist'),
        ]);
        [inv, trade, wish] = await dao.listsFor(a.id);
        await dao.replaceMirror(
          inv.id,
          [
            _row(inv.id, 0, 'Bolt', count: 3).copyWith(tradeCount: const Value(2)),
            _row(inv.id, 1, 'Ring', count: 2),
          ],
          pulledAt: 1,
        );
      });

      test('a Tradelist reads its Inventory; other lists read themselves', () async {
        final dao = db.externalDao;
        expect((await dao.inventoryFor(trade))?.id, inv.id);
        expect(await dao.mirrorIdOf(trade), inv.id);
        expect(await dao.mirrorIdOf(inv), inv.id);
        expect(await dao.mirrorIdOf(wish), wish.id);
        expect([for (final l in await dao.listsSharing(inv.id)) l.kind], ['inventory', 'tradelist']);
        expect([for (final l in await dao.listsSharing(wish.id)) l.kind], ['wishlist']);
      });

      test("a Tradelist's removal is checked against the Inventory's trade count", () async {
        final dao = db.externalDao;
        final bolt = (await dao.watchEntries(inv.id).first).firstWhere((e) => e.name == 'Bolt');
        expect(await dao.stageRemoval(list: trade, row: bolt, quantity: 5), 2, reason: 'capped at the 2 for trade');

        // Deckbox now has only 1 of them for trade.
        await dao.replaceMirror(
          inv.id,
          [_row(inv.id, 0, 'Bolt', count: 3).copyWith(tradeCount: const Value(1))],
          pulledAt: 2,
        );
        await dao.revalidate(trade);
        expect((await dao.stagedFor(trade.id)).single.flag, 'short:1');
      });

      test("a Tradelist addition marks free copies: capped, merged, flagged when the row moves", () async {
        final dao = db.externalDao;
        // Bolt: 3 owned, 2 for trade — 1 free. Ring: 2 owned, none for trade.
        final rows = await dao.watchEntries(inv.id).first;
        final bolt = rows.firstWhere((e) => e.name == 'Bolt');
        final ring = rows.firstWhere((e) => e.name == 'Ring');
        expect(ExternalDao.freeOf(bolt), 1);

        expect(await dao.stageMark(list: trade, row: bolt, quantity: 5), 1, reason: 'only 1 free');
        expect(await dao.stageMark(list: trade, row: bolt), 0, reason: 'nothing left to mark');
        expect(await dao.stageMark(list: trade, row: ring), 1);
        expect(await dao.stageMark(list: trade, row: ring), 1);
        final marks = {for (final s in await dao.stagedFor(trade.id)) s.name: s};
        expect(marks['Ring']!.quantity, 2, reason: 'marking the same row again adds up');
        expect(marks['Ring']!.direction, 'add');
        expect(marks['Ring']!.identityKey, ring.identityKey);

        // On Deckbox, a Ring went up for trade elsewhere — 1 free now.
        await dao.replaceMirror(
          inv.id,
          [
            _row(inv.id, 0, 'Bolt', count: 3).copyWith(tradeCount: const Value(2)),
            _row(inv.id, 1, 'Ring', count: 2).copyWith(tradeCount: const Value(1)),
          ],
          pulledAt: 3,
        );
        await dao.revalidate(trade);
        final flags = {for (final s in await dao.stagedFor(trade.id)) s.name: s.flag};
        expect(flags, {'Bolt': null, 'Ring': 'short:1'});
      });

      group('a row edit, applied (mirror_editing.md)', () {
        ExternalEntriesCompanion lp(String name, String printingId) => ExternalEntriesCompanion(
              printingId: Value(printingId),
              condition: const Value('Good (Lightly Played)'),
              identityKey: Value('$name|$printingId|Good (Lightly Played)|English|'),
              conditionCode: const Value(1),
            );

        test('removals and marks follow the row; additions stay as they were', () async {
          final dao = db.externalDao;
          final bolt = (await dao.watchEntries(inv.id).first).firstWhere((e) => e.name == 'Bolt');
          await dao.stageRemoval(list: inv, row: bolt, quantity: 2);
          await dao.stageMark(list: trade, row: bolt);
          await dao.stageAdditionLike(bolt);

          await dao.applyRowEdit(bolt, lp('Bolt', '114480'));

          final edited = (await dao.watchEntries(inv.id).first).firstWhere((e) => e.name == 'Bolt');
          expect((edited.id, edited.condition, edited.conditionCode, edited.count, edited.tradeCount),
              (bolt.id, 'Good (Lightly Played)', 1, 3, 2));
          final removal = (await dao.stagedFor(inv.id)).firstWhere((s) => s.direction == 'remove');
          expect((removal.identityKey, removal.stageKey, removal.conditionCode, removal.quantity, removal.flag),
              (edited.identityKey, edited.identityKey, 1, 2, null));
          final mark = (await dao.stagedFor(trade.id)).single;
          expect((mark.identityKey, mark.stageKey, mark.flag), (edited.identityKey, ExternalDao.markKey(edited), null));
          final addition = (await dao.stagedFor(inv.id)).firstWhere((s) => s.direction == 'add');
          expect((addition.identityKey, addition.conditionCode), (null, bolt.conditionCode),
              reason: 'a card in hand keeps its own variant');
        });

        test('into a variant the mirror has: one row, both counts, staged changes added up', () async {
          final dao = db.externalDao;
          await dao.replaceMirror(
            inv.id,
            [
              _row(inv.id, 0, 'Bolt', count: 3).copyWith(tradeCount: const Value(1)),
              _row(inv.id, 1, 'Bolt', count: 1, printingId: '999')
                  .copyWith(condition: const Value('Good (Lightly Played)'), identityKey: const Value('Bolt|999|Good (Lightly Played)|English|')),
              _row(inv.id, 2, 'Ring', count: 2),
            ],
            pulledAt: 2,
          );
          final [a, b, _] = await dao.watchEntries(inv.id).first;
          await dao.stageRemoval(list: inv, row: a, quantity: 2);
          await dao.stageRemoval(list: inv, row: b);

          await dao.applyRowEdit(a, lp('Bolt', '999'));

          final rows = await dao.watchEntries(inv.id).first;
          expect([for (final r in rows) (r.id, r.position, r.printingId, r.count, r.tradeCount)], [
            (a.id, 0, '999', 4, 1),
            (rows.last.id, 1, '114480', 2, 0),
          ], reason: "the edited row survives (E4); Ring moves up into the gone row's place");
          final removals = await dao.stagedFor(inv.id);
          expect([for (final s in removals) (s.identityKey, s.quantity)], [('Bolt|999|Good (Lightly Played)|English|', 3)]);
        });
      });

      test('the folder counts a Tradelist from its Inventory, for trade', () async {
        final counts = await db.externalDao.watchCounts().first;
        expect(counts[inv.id], (copies: 5, forTrade: 2, unique: 2, tradeUnique: 1));
        expect(counts.containsKey(trade.id), isFalse, reason: 'a Tradelist stores no rows');
      });
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
