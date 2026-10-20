import 'package:flutter_test/flutter_test.dart';
import 'package:mtg_homunculus/features/card_lookup/data/cards_database.dart';
import 'package:mtg_homunculus/features/card_lookup/data/collection_database.dart';
import 'package:mtg_homunculus/features/card_lookup/external/removal_match.dart';
import 'package:mtg_homunculus/features/card_lookup/services/card_identifier.dart';

Card card(String id, {String name = 'Lightning Bolt', String set = 'm10', String num = '146'}) => Card(
      id: id,
      oracleId: 'oracle-$name',
      name: name,
      setCode: set,
      collectorNumber: num,
      lang: 'en',
      fullArt: false,
      hasBack: false,
      imageStatus: 3,
      finishes: 1,
    );

var _nextId = 0;

ExternalEntry row(String name, {String? cardId, bool any = false, int count = 1, String condition = 'Near Mint'}) =>
    ExternalEntry(
      id: ++_nextId,
      listId: 1,
      position: _nextId,
      count: count,
      tradeCount: 0,
      printingId: any ? '' : 'p$_nextId',
      condition: condition,
      language: 'English',
      foil: '',
      rowFlags: '',
      identityKey: '$name|$_nextId',
      name: name,
      edition: '',
      editionCode: '',
      cardNumber: '',
      printingNote: '',
      cardId: any ? null : cardId,
      cardRef: cardId,
      anyPrinting: any,
    );

void main() {
  // The list: Bolt in M10 and 2XM, a generic Bolt, and an unrelated card.
  late ExternalEntry m10, xm, anyBolt, ring;
  late List<ExternalEntry> rows;
  setUp(() {
    m10 = row('Lightning Bolt', cardId: 'bolt-m10');
    xm = row('Lightning Bolt', cardId: 'bolt-2xm');
    anyBolt = row('Lightning Bolt', any: true, cardId: 'bolt-standin');
    ring = row('Sol Ring', cardId: 'ring-c18');
    rows = [m10, xm, anyBolt, ring];
  });

  final boltM10 = card('bolt-m10');
  final boltA25 = card('bolt-a25', set: 'a25', num: '141');
  final bolt2xm = card('bolt-2xm', set: '2xm', num: '117');

  RemovalMatch resolve(
    List<Card> candidates, {
    required bool known,
    List<ExternalEntry>? on,
    Set<ExternalEntry> staged = const {},
  }) =>
      RemovalMatcher.resolve(
        rows: on ?? rows,
        left: (e) => staged.contains(e) ? 0 : e.count,
        candidates: candidates,
        printingKnown: known,
      );

  group('the printing read off the card', () {
    test('with a row of its own, it is asked against the generic row', () {
      final m = resolve([boltM10], known: true);
      expect((m as AskRows).rows, [m10, anyBolt]);
    });

    test('with a row of its own and no generic row, it is staged — the other printing is not offered', () {
      final m = resolve([boltM10], known: true, on: [m10, xm]);
      expect((m as StageRow).row, m10);
    });

    test('with no row of its own, it is the generic row — no question', () {
      final m = resolve([boltA25], known: true);
      expect((m as StageRow).row, anyBolt);
    });

    test('with no row of its own and no generic row, it is not on the list', () {
      final m = resolve([boltA25], known: true, on: [m10, xm, ring]);
      expect(m, isA<NotOnList>());
    });

    test('its row all staged leaves the generic row', () {
      final m = resolve([boltM10], known: true, staged: {m10});
      expect((m as StageRow).row, anyBolt);
    });

    test('everything it could be already staged says so', () {
      final m = resolve([boltM10], known: true, staged: {m10, anyBolt});
      expect((m as AllStaged).name, 'Lightning Bolt');
    });
  });

  group('the card known, not its printing', () {
    test('every row of the card is offered', () {
      final m = resolve([boltM10, bolt2xm, boltA25], known: false);
      expect((m as AskRows).rows, [m10, xm, anyBolt]);
    });

    test('a staged row drops out, and one left is staged', () {
      final m = resolve([boltM10, bolt2xm], known: false, staged: {m10, xm});
      expect((m as StageRow).row, anyBolt);
    });

    test('a card not on the list is not offered anything', () {
      final m = resolve([card('dragon-c17', name: 'The Ur-Dragon')], known: false);
      expect((m as NotOnList).name, 'The Ur-Dragon');
    });
  });

  group('only the image', () {
    test('rows of every card guessed are offered, the other card included', () {
      final m = resolve([boltM10, card('ring-c20', name: 'Sol Ring')], known: false);
      expect((m as AskRows).rows, [m10, xm, anyBolt, ring]);
    });

    test('one row left is still asked: it may be the wrong card', () {
      final m = resolve(
        [boltM10, card('ring-c20', name: 'Sol Ring')],
        known: false,
        on: [ring],
      );
      expect((m as AskRows).rows, [ring]);
    });
  });

  group('reading the printing', () {
    Identification id(List<Card> c, {String? set, String? number}) => Identification(
          candidates: c,
          via: IdentifiedVia.hashAndOcr,
          readSetCode: set,
          readCollectorNumber: number,
        );

    test('a set code or number agreeing with the one candidate', () {
      expect(RemovalMatcher.printingRead(id([boltM10], set: 'M10')), isTrue);
      expect(RemovalMatcher.printingRead(id([boltM10], number: '0146')), isTrue);
    });

    test('a lone hash match without a read does not count; nor do several candidates', () {
      expect(RemovalMatcher.printingRead(id([boltM10])), isFalse);
      expect(RemovalMatcher.printingRead(id([boltM10], set: 'a25')), isFalse);
      expect(RemovalMatcher.printingRead(id([boltM10, bolt2xm], set: 'm10')), isFalse);
    });
  });
}
