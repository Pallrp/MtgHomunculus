import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtg_homunculus/features/card_lookup/data/collection_database.dart';
import 'package:mtg_homunculus/features/card_lookup/external/deckbox_sheet_model.dart';

ExternalEntriesCompanion _row(
  int listId,
  int position,
  String name, {
  int count = 1,
  int tradeCount = 0,
  String? cardId = 'scry-1',
  bool any = false,
  int? condition = 0,
  String? language = 'en',
}) =>
    ExternalEntriesCompanion.insert(
      listId: listId,
      position: position,
      count: count,
      tradeCount: Value(tradeCount),
      printingId: any ? '' : '1$position',
      condition: condition == null ? '' : 'Near Mint',
      language: language == null ? '' : 'English',
      foil: '',
      rowFlags: '',
      identityKey: '$name|$position',
      name: name,
      edition: 'Magic 2010',
      editionCode: 'm10',
      cardNumber: '146',
      printingNote: '',
      anyPrinting: any,
      cardId: Value(any ? null : cardId),
      cardRef: Value(cardId),
      finish: Value(any ? null : 1),
      languageCode: Value(language),
      conditionCode: Value(condition),
    );

void main() {
  late CollectionDatabase db;
  late ExternalList inv;

  setUp(() async {
    db = CollectionDatabase.forTesting(NativeDatabase.memory());
    final dao = db.externalDao;
    final a = await dao.upsertAccount(provider: 'deckbox', username: 'u');
    await dao.syncLists(a.id, [
      (remoteId: 1, kind: 'inventory', name: 'Inventory'),
      (remoteId: 2, kind: 'tradelist', name: 'Tradelist'),
    ]);
    inv = (await dao.listsFor(a.id)).first;
    await dao.replaceMirror(
      inv.id,
      [
        _row(inv.id, 0, 'Lightning Bolt', count: 3, cardId: 'bolt', tradeCount: 1),
        _row(inv.id, 1, 'Sol Ring', count: 2, any: true, cardId: 'ring-standin'),
        _row(inv.id, 2, 'Llanowar Elves', cardId: 'elves'),
      ],
      pulledAt: 1,
    );
  });
  tearDown(() => db.close());

  Future<DeckboxSheetModel> model(ExternalList list, {String query = ''}) async => DeckboxSheetModel(
        list: list,
        mirror: await db.externalDao.watchEntries(list.id).first,
        staged: await db.externalDao.stagedFor(list.id),
        query: query,
      );

  Future<int> add(String name, {String? cardId, bool any = false, int? condition = 0, String? language = 'en'}) =>
      db.externalDao.stageAddition(
        listId: inv.id,
        name: name,
        cardId: cardId,
        cardRef: cardId,
        anyPrinting: any,
        finish: any ? null : 1,
        languageCode: language,
        conditionCode: condition,
      );

  test('an addition of an exact variant already there reads +N, and marks that row', () async {
    await add('Lightning Bolt', cardId: 'bolt');
    await add('Lightning Bolt', cardId: 'bolt');
    final m = await model(inv);
    final a = m.additions.single;
    expect(m.additionPill(a), '+2');
    expect(m.added[a.existing!.id], 2);
  });

  test('another condition, or a new printing, is a new row: xN', () async {
    await add('Lightning Bolt', cardId: 'bolt', condition: 2);
    await add('Counterspell', cardId: 'cs');
    final m = await model(inv);
    expect(m.additions.map(m.additionPill), ['x1', 'x1']);
    expect(m.added, isEmpty);
  });

  test('a blank generic does not add to a Near Mint English one (device test 2026-10-15)', () async {
    await add('Sol Ring', any: true, condition: null, language: null);
    await add('Sol Ring', any: true);
    final m = await model(inv);
    final pills = {
      for (final a in m.additions) a.staged.conditionCode: m.additionPill(a),
    };
    expect(pills, {null: 'x1', 0: '+1'});
  });

  test('a removal reads against the row, and a flagged one is not counted to send', () async {
    final dao = db.externalDao;
    final rows = await dao.watchEntries(inv.id).first;
    await dao.stageRemoval(list: inv, row: rows[0], quantity: 2);
    await dao.stageRemoval(list: inv, row: rows[2]);
    await add('Counterspell', cardId: 'cs');

    var m = await model(inv);
    expect(m.removals.map(m.removalPill), containsAll(['−2 of 3', '−1 of 1']));
    expect(m.removed[rows[0].id], 2);
    expect(m.sendable, 3);

    // Elves vanish from Deckbox: its removal is flagged and drops out of the push.
    await dao.replaceMirror(inv.id, [_row(inv.id, 0, 'Lightning Bolt', count: 3, cardId: 'bolt')], pulledAt: 2);
    await dao.revalidate(inv);
    m = await model(inv);
    expect(m.flagged, 1);
    expect(m.sendable, 2);
    expect(m.removals.map(m.removalPill), contains('gone'));
  });

  test("a Tradelist shows only rows for trade, counted by what's for trade", () async {
    final trade = (await db.externalDao.listsFor(inv.accountId))[1];
    await db.externalDao.replaceMirror(
      trade.id,
      [
        _row(trade.id, 0, 'Lightning Bolt', count: 3, tradeCount: 1),
        _row(trade.id, 1, 'Llanowar Elves'),
      ],
      pulledAt: 1,
    );
    final m = await model(trade);
    expect(m.onDeckbox.map((e) => e.name), ['Lightning Bolt']);
    expect(m.copies, 1);
  });

  test("an Inventory addition up for trade gets the Tradelist half: +N onto a row partly for trade, else xN", () async {
    final dao = db.externalDao;
    Future<void> stage(String name, String id, bool trade) => dao.stageAddition(
          listId: inv.id,
          name: name,
          cardId: id,
          cardRef: id,
          anyPrinting: false,
          finish: 1,
          languageCode: 'en',
          conditionCode: 0,
          forTrade: trade,
        );
    await stage('Lightning Bolt', 'bolt', true); // its row has 1 for trade
    await stage('Counterspell', 'cs', true); // no row at all
    await stage('Llanowar Elves', 'elves', false); // not for trade
    final m = await model(inv);
    final halves = {for (final a in m.additions) a.staged.name: m.tradeHalf(a)};
    expect(halves, {'Lightning Bolt': '+1', 'Counterspell': 'x1', 'Llanowar Elves': null});
  });

  test("a Tradelist's additions are marks: x onto a row new to trade, + onto one partly for trade", () async {
    final dao = db.externalDao;
    final trade = (await dao.listsFor(inv.accountId))[1];
    final rows = await dao.watchEntries(inv.id).first;
    final bolt = rows.firstWhere((e) => e.name == 'Lightning Bolt'); // 3 owned, 1 for trade
    final elves = rows.firstWhere((e) => e.name == 'Llanowar Elves'); // 1 owned, none for trade
    await dao.stageMark(list: trade, row: bolt, quantity: 2);
    await dao.stageMark(list: trade, row: elves);

    final m = DeckboxSheetModel(list: trade, mirror: rows, staged: await dao.stagedFor(trade.id));
    final pills = {for (final a in m.additions) a.staged.name: m.additionPill(a)};
    expect(pills, {'Lightning Bolt': '+2', 'Llanowar Elves': 'x1'});
    final caps = {for (final a in m.additions) a.staged.name: m.markCap(a)};
    expect(caps, {'Lightning Bolt': 2, 'Llanowar Elves': 1});
    expect(m.onDeckbox.map((e) => e.name), ['Lightning Bolt'], reason: 'the Elves are not for trade yet');
    expect(m.sendable, 2);

    // The Elves leave the Inventory: their mark is flagged, and not sent.
    await dao.replaceMirror(inv.id, [rows.first.toCompanion(true)], pulledAt: 2);
    await dao.revalidate(trade);
    final after = DeckboxSheetModel(
      list: trade,
      mirror: await dao.watchEntries(inv.id).first,
      staged: await dao.stagedFor(trade.id),
    );
    expect(after.sendable, 1);
    expect(after.flagged, 1);
  });

  test('the search narrows every section', () async {
    await add('Counterspell', cardId: 'cs');
    final m = await model(inv, query: 'bolt');
    expect(m.onDeckbox.map((e) => e.name), ['Lightning Bolt']);
    expect(m.additions, isEmpty);
    expect(m.unique, 3, reason: 'the header counts stay the whole list');
  });
}
