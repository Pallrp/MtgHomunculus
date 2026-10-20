import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mtg_homunculus/features/card_lookup/external/deckbox/deckbox_row_panel.dart';

void main() {
  // A real panel: a Strixhaven row on the test account, 4 owned, 4 for trade,
  // Near Mint, English, no flags, no tags (2026-10-20).
  final html = File('test/fixtures/deckbox_row_panel.html.txt').readAsStringSync();

  test('reads the row, its ids and its values from the panel', () {
    final p = DeckboxRowPanel.parse(html);
    expect(p.rowId, '464146194');
    expect(p.cardId, '22899');
    expect(p.setId, 3927970);
    expect((p.count, p.tradeCount), ('4', '4'));
    expect((p.editionId, p.conditionId, p.languageId), (55902, 2, 1));
    expect(p.flags, isEmpty);
    expect(p.tagIds, '');
    expect(p.price, isNull, reason: 'a premium field, absent here');
  });

  test("lists the card's printings with Deckbox's edition ids", () {
    final p = DeckboxRowPanel.parse(html);
    expect(p.editions.map((e) => e.id), [0, 55902, 56182, 57857, 56285]);
    expect(p.editions.first.toString(), '[Unspecified Edition]');
    final promo = p.editions.firstWhere((e) => e.id == 57857);
    expect((promo.name, promo.code, promo.number), ('Promo Pack: Strixhaven: School of Mages', 'PP_STX', '7'));
    expect(p.edition?.toString(), 'Strixhaven: School of Mages (STX #7)');
  });

  test('saves the whole row back, changing only what is given', () {
    final p = DeckboxRowPanel.parse(html);
    final data = jsonDecode(p.saveData(conditionId: 3, flags: [...p.flags, 'is_foil'])) as Map;
    expect(data, {
      'id': '464146194',
      'card_id': '22899',
      'count': '4',
      'trade_count': '4',
      'details': {'card_edition_id': '55902', 'condition_id': '3', 'language_id': '1', 'flags': 'is_foil'},
      'tag_ids': '',
    });
  });

  test('keeps flags and tags it does not change', () {
    final withFlags = html
        .replaceFirst("name: 'details[0][flags]',\n      initial: []", "name: 'details[0][flags]',\n      initial: [\"is_signed\", \"is_altered\"]")
        .replaceFirst("id: '_pes_tag_ids',", "id: '_pes_tag_ids', initial: [12, 40],");
    final p = DeckboxRowPanel.parse(withFlags);
    expect(p.flags, ['is_signed', 'is_altered']);
    expect(p.tagIds, '12,40');
    final details = (jsonDecode(p.saveData(languageId: 2)) as Map)['details'] as Map;
    expect(details['flags'], 'is_signed,is_altered');
  });

  test('refuses a panel missing what a save needs', () {
    expect(() => DeckboxRowPanel.parse(html.replaceAll('_pes_count', '_x')), throwsFormatException);
    expect(() => DeckboxRowPanel.parse(html.replaceAll('details[0][flags]', 'x')), throwsFormatException);
  });
}
