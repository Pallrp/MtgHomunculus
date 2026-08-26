import 'package:flutter_test/flutter_test.dart';
import 'package:mtg_homunculus/features/card_lookup/data/collection_database.dart';
import 'package:mtg_homunculus/features/card_lookup/widgets/listing_sheet.dart';

Entry entry({
  required int id,
  String name = 'Swamp',
  String set = 'm21',
  String collector = '267',
  int addedAt = 0,
  int quantity = 1,
}) =>
    Entry(
      id: id,
      listId: 1,
      cardId: 'c$id',
      finish: Finish.nonfoil,
      language: 'en',
      condition: Condition.nearMint,
      quantity: quantity,
      addedAt: addedAt,
      snapName: name,
      snapSetCode: set,
      snapSetName: set.toUpperCase(),
      snapCollector: collector,
    );

void main() {
  final rows = [
    entry(id: 1, name: 'Swamp', set: 'm21', collector: '267', addedAt: 100),
    entry(id: 2, name: 'Colossal Dreadmaw', set: 'xln', collector: '180', addedAt: 300),
    entry(id: 3, name: 'anthem', set: 'lci', collector: '5', addedAt: 200),
  ];

  group('scanned', () {
    test('is newest first — the order the list arrives in', () {
      expect(EntrySort.scanned.apply(rows).map((e) => e.id), [2, 3, 1]);
    });
  });

  group('name', () {
    test('is case-insensitive, or lowercase names sort after everything', () {
      expect(EntrySort.name.apply(rows).map((e) => e.id), [3, 2, 1]);
    });
  });

  group('set', () {
    test('groups by set, then by collector number', () {
      expect(EntrySort.set.apply(rows).map((e) => e.id), [3, 1, 2]);
    });
  });

  group('every order', () {
    test('leaves the input untouched', () {
      final before = rows.map((e) => e.id).toList();
      for (final s in EntrySort.values) {
        s.apply(rows);
      }
      expect(rows.map((e) => e.id).toList(), before,
          reason: 'sorting a list must not reorder the caller\'s copy');
    });

    test('keeps every row', () {
      for (final s in EntrySort.values) {
        expect(s.apply(rows), hasLength(rows.length), reason: s.label);
      }
    });

    test('handles an empty list', () {
      for (final s in EntrySort.values) {
        expect(s.apply(const []), isEmpty, reason: s.label);
      }
    });
  });
}
