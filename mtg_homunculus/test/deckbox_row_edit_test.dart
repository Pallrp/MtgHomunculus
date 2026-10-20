import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mtg_homunculus/features/card_lookup/external/deckbox/deckbox_mapping.dart';
import 'package:mtg_homunculus/features/card_lookup/external/deckbox/deckbox_row_edit.dart';
import 'package:mtg_homunculus/features/card_lookup/external/deckbox/deckbox_row_panel.dart';

void main() {
  // The real panel: STX #7, 4 owned / 4 for trade, Near Mint, English, no flags.
  final html = File('test/fixtures/deckbox_row_panel.html.txt').readAsStringSync();
  final panel = DeckboxRowPanel.parse(html);
  DeckboxRowPanel withFlags(List<String> flags) => DeckboxRowPanel.parse(html.replaceFirst(
      "name: 'details[0][flags]',\n      initial: []",
      "name: 'details[0][flags]',\n      initial: [${flags.map((f) => '"$f"').join(', ')}]"));

  const mirror = (
    printingId: '55902',
    condition: 'Near Mint',
    language: 'English',
    foil: '',
    rowFlags: '',
    count: 4,
    tradeCount: 4,
  );

  Map details(String data) => (jsonDecode(data) as Map)['details'] as Map;

  group('the check against the mirror row', () {
    test('the same row passes', () {
      expect(DeckboxRowEdit.mismatch(panel, mirror), isNull);
    });

    test('a changed field or count is named', () {
      expect(DeckboxRowEdit.mismatch(panel, (
        printingId: '55902', condition: 'Played', language: 'English', foil: '', rowFlags: '',
        count: 4, tradeCount: 4,
      )), contains('condition'));
      expect(DeckboxRowEdit.mismatch(panel, (
        printingId: '55902', condition: 'Near Mint', language: 'English', foil: '', rowFlags: '',
        count: 3, tradeCount: 4,
      )), contains('count'));
    });

    test('counts can be left out — after a merge they are a sum', () {
      final merged = (
        printingId: '55902', condition: 'Near Mint', language: 'English', foil: '', rowFlags: '',
        count: 9, tradeCount: 5,
      );
      expect(DeckboxRowEdit.mismatch(panel, merged), isNotNull);
      expect(DeckboxRowEdit.mismatch(panel, merged, counts: false), isNull);
    });

    test("a Wishlist's row has no count for trade to compare", () {
      final wish = (
        printingId: '55902', condition: 'Near Mint', language: 'English', foil: '', rowFlags: '',
        count: 4, tradeCount: null,
      );
      expect(DeckboxRowEdit.mismatch(panel, wish), isNull);
    });

    test('flags read in the export\'s columns and order', () {
      final p = withFlags(['is_altered', 'is_foil', 'is_signed']);
      expect(DeckboxRowEdit.rawOf(p).rowFlags, 'Signed,Altered Art');
      expect(DeckboxRowEdit.rawOf(p).foil, 'foil');
    });
  });

  group('the save', () {
    test('sends only what changed, mapped to Deckbox ids', () {
      final d = details(DeckboxRowEdit.saveData(
        panel,
        const RowEdit(condition: (code: 1), language: (code: 'de')),
      ));
      expect(d, {'card_edition_id': '55902', 'condition_id': '3', 'language_id': '2', 'flags': ''});
    });

    test('foil toggles within the flags, keeping signed', () {
      final p = withFlags(['is_signed']);
      expect(details(DeckboxRowEdit.saveData(p, const RowEdit(foil: true)))['flags'], 'is_signed,is_foil');
      final both = withFlags(['is_foil', 'is_signed']);
      expect(details(DeckboxRowEdit.saveData(both, const RowEdit(foil: false)))['flags'], 'is_signed');
    });

    test('any — condition, language, printing — is id 0', () {
      final d = details(DeckboxRowEdit.saveData(
        panel,
        RowEdit(condition: (code: null), language: (code: null), edition: panel.editions.first),
      ));
      expect((d['card_edition_id'], d['condition_id'], d['language_id']), ('0', '0', '0'));
    });

    test('a language Deckbox lacks is refused before anything is sent', () {
      expect(() => DeckboxRowEdit.saveData(panel, const RowEdit(language: (code: 'ph'))), throwsArgumentError);
    });
  });

  group('after the save', () {
    test('the row reads as the export will show it', () {
      final promo = panel.editions.firstWhere((e) => e.code == 'PP_STX');
      final after = DeckboxRowEdit.after(panel, RowEdit(edition: promo, condition: (code: 2), foil: true));
      expect(after, (
        printingId: '57857',
        condition: 'Played',
        language: 'English',
        foil: 'foil',
        rowFlags: '',
        count: 4,
        tradeCount: 4,
      ));
    });

    test('any printing leaves the printing id empty', () {
      expect(DeckboxRowEdit.after(panel, RowEdit(edition: panel.editions.first)).printingId, '');
    });

    test('the identity is rebuilt with the name and flag columns kept', () {
      final export = {
        'Name': 'Academic Probation',
        'Printing Id': '55902',
        'Condition': 'Near Mint',
        'Language': 'English',
        'Foil': '',
        'Signed': 'signed',
      };
      final old = DeckboxMapping.identityOf(export);
      final after = DeckboxRowEdit.after(panel, const RowEdit(condition: (code: 1), foil: true));
      expect(
        DeckboxRowEdit.identityAfter(old, after),
        DeckboxMapping.identityOf({...export, 'Condition': 'Good (Lightly Played)', 'Foil': 'foil'}),
      );
    });

    test('the panel opened again confirms the save', () {
      final after = DeckboxRowEdit.after(panel, const RowEdit(condition: (code: 1)));
      final reopened = DeckboxRowPanel.parse(html.replaceFirst('initial: [2]', 'initial: [3]'));
      expect(DeckboxRowEdit.mismatch(reopened, after, counts: false), isNull);
      expect(DeckboxRowEdit.mismatch(panel, after, counts: false), isNotNull, reason: 'not saved');
    });
  });

  group('matching printings for Change Version', () {
    ({String id, String setCode, String setName, String number}) p(String id, String set, String name, String n) =>
        (id: id, setCode: set, setName: name, number: n);

    test('by code and number, then by set name and number', () {
      final m = DeckboxRowEdit.matchPrintings(panel.editions, [
        p('stx7', 'stx', 'Strixhaven: School of Mages', '7'),
        p('stx287', 'stx', 'Strixhaven: School of Mages', '287'),
        p('pp', 'pstx', 'Promo Pack: Strixhaven: School of Mages', '7'),
        p('ptc', 'pstx', 'Strixhaven Promos', '7s'),
      ]);
      expect({for (final e in m.entries) e.key: e.value.id}, {'stx7': 55902, 'stx287': 56182, 'pp': 57857});
    });

    test('by set name alone when each side has one printing in it', () {
      final editions = [
        const DeckboxEdition(id: 0, name: '', code: '', number: ''),
        const DeckboxEdition(id: 6225, name: 'Limited Edition Alpha', code: '1E', number: '106'),
        const DeckboxEdition(id: 9, name: 'Commander Legends Etched', code: 'CMR_E', number: '1'),
      ];
      final m = DeckboxRowEdit.matchPrintings(editions, [p('lea', 'lea', 'Limited Edition Alpha', '198')]);
      expect(m['lea']?.id, 6225);
    });
  });
}
