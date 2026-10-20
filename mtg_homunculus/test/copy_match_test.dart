import 'package:flutter_test/flutter_test.dart';
import 'package:mtg_homunculus/features/card_lookup/data/collection_database.dart';
import 'package:mtg_homunculus/features/card_lookup/external/copy_match.dart';

var _id = 0;

ExternalEntry row(String name, {String? cardId, bool any = false, int count = 1, int? condition = 0}) =>
    ExternalEntry(
      id: ++_id,
      listId: 1,
      position: _id,
      count: count,
      tradeCount: 0,
      printingId: any ? '' : 'p$_id',
      condition: 'x',
      language: 'English',
      foil: '',
      rowFlags: '',
      identityKey: '$name|$_id',
      name: name,
      edition: '',
      editionCode: '',
      cardNumber: '',
      printingNote: '',
      cardId: any ? null : cardId,
      cardRef: cardId,
      anyPrinting: any,
      finish: any ? null : 1,
      languageCode: any ? null : 'en',
      conditionCode: any ? null : condition,
    );

CardLine line(String name, {String? cardId, bool any = false, int quantity = 1, int? condition = 0}) => CardLine(
      name: name,
      cardId: any ? null : cardId,
      cardRef: cardId,
      anyPrinting: any,
      finish: any ? null : 1,
      languageCode: any ? null : 'en',
      conditionCode: any ? null : condition,
      setCode: 'm10',
      setName: '',
      collectorNumber: '146',
      quantity: quantity,
      source: const FromAppEntry(1),
    );

void main() {
  List<LineMatch> match(
    List<CardLine> lines,
    List<ExternalEntry> rows, {
    Map<int, ExternalEntry> chosen = const {},
    Set<int> skipped = const {},
  }) =>
      CopyMatcher.matchAll(lines: lines, rows: rows, left: (e) => e.count, chosen: chosen, skipped: skipped);

  test('an exact printing and variant is matched automatically', () {
    final nm = row('Bolt', cardId: 'b', count: 2), lp = row('Bolt', cardId: 'b', condition: 1);
    final m = match([line('Bolt', cardId: 'b')], [nm, lp]).single as Placed;
    expect(m.row, nm);
    expect(m.chosen, isFalse);
  });

  test('the only row it could be is treated as exact', () {
    final lp = row('Bolt', cardId: 'b', condition: 1);
    expect((match([line('Bolt', cardId: 'b')], [lp]).single as Placed).row, lp);
  });

  test('several rows, none exact, are the user\'s to choose — a generic row among them', () {
    final lp = row('Bolt', cardId: 'b', condition: 1), any = row('Bolt', any: true);
    final m = match([line('Bolt', cardId: 'b')], [lp, any]).single as Choose;
    expect(m.rows, [lp, any]);
  });

  test('a choice made places the line; a skip leaves it', () {
    final lp = row('Bolt', cardId: 'b', condition: 1), any = row('Bolt', any: true);
    final lines = [line('Bolt', cardId: 'b'), line('Bolt', cardId: 'b', condition: 2)];
    final m = match(lines, [lp, any], chosen: {0: any}, skipped: {1});
    expect((m[0] as Placed).row, any);
    expect((m[0] as Placed).chosen, isTrue);
    expect((m[1] as Unplaced).skippedByUser, isTrue);
  });

  test('not on Deckbox is skipped, and so is a mirrored row with no printing', () {
    final m = match([line('Bolt', cardId: 'b'), line('Odd', cardId: null)], [row('Ring', cardId: 'r')]);
    expect((m[0] as Unplaced).reason, "Deckbox doesn't have it");
    expect((m[1] as Unplaced).reason, 'Not matched to a printing');
  });

  test('more copies than Deckbox has: what fits is staged, the rest is excess', () {
    final nm = row('Bolt', cardId: 'b', count: 2);
    final m = match([line('Bolt', cardId: 'b', quantity: 3)], [nm]).single as Placed;
    expect(m.quantity, 2);
    expect(m.excess, 1);
  });

  test('two lines never claim the same copy', () {
    final nm = row('Bolt', cardId: 'b');
    final m = match([line('Bolt', cardId: 'b'), line('Bolt', cardId: 'b')], [nm]);
    expect(m[0], isA<Placed>());
    expect((m[1] as Unplaced).reason, 'All of it is already staged to remove');
    expect(CopyMatcher.staged(m), 1);
  });

  test('a generic line goes to any row of the card', () {
    final nm = row('Bolt', cardId: 'b');
    expect((match([line('Bolt', any: true)], [nm]).single as Placed).row, nm);
  });
}
