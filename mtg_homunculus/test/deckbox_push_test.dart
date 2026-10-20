import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mtg_homunculus/features/card_lookup/external/deckbox/deckbox_csv.dart';
import 'package:mtg_homunculus/features/card_lookup/external/deckbox/deckbox_mapping.dart';
import 'package:mtg_homunculus/features/card_lookup/external/deckbox/deckbox_push.dart';

PendingAddition _add({
  String name = 'Titan Forge',
  String? cardId = '91a3c3ba-6dbb-454c-86ad-064875382499',
  bool anyPrinting = false,
  int? finish = DeckboxMapping.nonfoil,
  String? languageCode = 'en',
  int? conditionCode = 0,
  String setCode = 'eoc',
  String setName = 'Edge of Eternities Commander',
  String collectorNumber = '146',
  int quantity = 1,
  bool forTrade = false,
}) =>
    (
      id: 1,
      name: name,
      cardId: cardId,
      anyPrinting: anyPrinting,
      finish: finish,
      languageCode: languageCode,
      conditionCode: conditionCode,
      setCode: setCode,
      setName: setName,
      collectorNumber: collectorNumber,
      quantity: quantity,
      forTrade: forTrade,
    );

void main() {
  group('writing an addition', () {
    test('an ordinary printing goes by its Scryfall ID (D4 p3, p4)', () {
      final r = DeckboxImportFile.rowFor(_add(quantity: 2, languageCode: 'ja', conditionCode: 2));
      expect(r.refusal, isNull);
      expect(r.fields!['Scryfall ID'], '91a3c3ba-6dbb-454c-86ad-064875382499');
      expect(r.fields!['Count'], '2');
      expect(r.fields!['Language'], 'Japanese');
      expect(r.fields!['Condition'], 'Played');
      expect(r.fields!['Foil'], '');
    });

    test('a generic row goes by name only — never its stand-in Scryfall ID (D9 w5)', () {
      final r = DeckboxImportFile.rowFor(_add(
        name: 'Sol Ring',
        cardId: null,
        anyPrinting: true,
        finish: null,
        languageCode: null,
        conditionCode: null,
      ));
      expect(r.fields!['Name'], 'Sol Ring');
      expect(r.fields!['Scryfall ID'], isNull);
      expect(r.fields!['Edition'], isNull);
      expect(r.fields!['Condition'], '');
      expect(r.fields!['Language'], '');
    });

    test('a generic row keeps the attributes it does set', () {
      final r = DeckboxImportFile.rowFor(_add(
        name: 'Lightning Bolt',
        cardId: null,
        anyPrinting: true,
        finish: DeckboxMapping.foil,
        languageCode: 'ja',
        conditionCode: 2,
      ));
      expect(r.fields!['Foil'], 'foil');
      expect(r.fields!['Language'], 'Japanese');
      expect(r.fields!['Condition'], 'Played');
    });

    test("etched in MH2 goes by Deckbox's etched edition, without a Scryfall ID (D4 p7)", () {
      final r = DeckboxImportFile.rowFor(_add(
        name: 'Aeromoeba',
        cardId: '25de0eb6-94f5-440f-8201-cc7dad2f0805',
        finish: DeckboxMapping.etched,
        setCode: 'mh2',
        setName: 'Modern Horizons 2',
        collectorNumber: '389',
      ));
      expect(r.fields!['Edition'], 'Modern Horizons 2 Etched');
      expect(r.fields!['Edition Code'], 'MH2_E');
      expect(r.fields!['Scryfall ID'], '');
      expect(r.fields!['Foil'], '', reason: '"etched" is refused as a foil value (D4 p6)');
    });

    test('Secret Lair etched is written as foil, by Scryfall ID (decided 2026-10-15)', () {
      final r = DeckboxImportFile.rowFor(_add(
        name: 'Plaguecrafter',
        cardId: '63a10efc-4b8d-4e32-90fb-50ab73810b59',
        finish: DeckboxMapping.etched,
        setCode: 'sld',
        collectorNumber: '1116',
      ));
      expect(r.fields!['Foil'], 'foil');
      expect(r.fields!['Scryfall ID'], '63a10efc-4b8d-4e32-90fb-50ab73810b59');
    });

    test('etched anywhere else is refused before upload, named', () {
      final r = DeckboxImportFile.rowFor(_add(finish: DeckboxMapping.etched, setCode: 'cmr'));
      expect(r.fields, isNull);
      expect(r.refusal, contains('CMR'));
    });

    test('the file quotes what needs quoting, and parses back', () {
      final csv = DeckboxImportFile.write([
        DeckboxImportFile.rowFor(_add(name: 'Edgar, Moonlit Sovereign')).fields!,
      ]);
      expect(csv, contains('"Edgar, Moonlit Sovereign"'));
      final back = DeckboxCsv.rows(csv).single;
      expect(back['Name'], 'Edgar, Moonlit Sovereign');
      expect(back.keys, DeckboxImportFile.header);
    });
  });

  group('up for trade (tradelist.md, decision 3)', () {
    test('a flagged addition carries its quantity as the trade count; an unflagged one 0', () {
      expect(DeckboxImportFile.rowFor(_add(quantity: 3, forTrade: true)).fields![DeckboxImportFile.tradeColumn], '3');
      expect(DeckboxImportFile.rowFor(_add(quantity: 3)).fields![DeckboxImportFile.tradeColumn], '0');
    });

    test('the column is only in the file when something is up for trade', () {
      final rows = [DeckboxImportFile.rowFor(_add(quantity: 2, forTrade: true)).fields!, DeckboxImportFile.rowFor(_add()).fields!];
      final plain = DeckboxCsv.rows(DeckboxImportFile.write(rows));
      expect(plain.first.containsKey(DeckboxImportFile.tradeColumn), isFalse);

      final mixed = DeckboxCsv.rows(DeckboxImportFile.write(rows, withTrade: true));
      expect([for (final r in mixed) r[DeckboxImportFile.tradeColumn]], ['2', '0'], reason: 'one file, mixed (T9)');
    });
  });

  group("reading the import's reply", () {
    String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

    test("Deckbox's own success reply is accepted", () {
      expect(ImportReply.read(fixture('deckbox_import_accepted.js.txt')), isA<ImportAccepted>());
    });

    test('a refusal names its rows and the cell Deckbox marked (D4 p2, verbatim)', () {
      final reply = ImportReply.read(fixture('deckbox_import_refused.js.txt'));
      expect(reply, isA<ImportRefused>());
      final row = (reply as ImportRefused).rows.single;
      expect(row.values['Name'], 'Titan Forge');
      expect(row.values['Edition'], 'Edge of Eternitys Comander');
      expect(row.errorColumns, {'Edition'});
      expect(row.reason, "Deckbox refused this row's edition");
    });

    test('a refused row matches the row that was sent', () {
      final sent = {
        'Name': 'Titan Forge',
        'Edition': 'Edge of Eternitys Comander',
        'Condition': 'Near Mint',
        'Foil': '',
        'Language': 'English',
      };
      final echoed = (ImportReply.read(fixture('deckbox_import_refused.js.txt')) as ImportRefused).rows.single;
      expect(echoed.echoKey, DeckboxImportFile.echoKey(sent));
    });

    test("the echo's columns are named by its own header — T6's file, refused on Count", () {
      final row = (ImportReply.read(fixture('deckbox_import_refused_t6.js.txt')) as ImportRefused).rows.single;
      expect(row.values['Count'], '0');
      expect(row.values['Name'], 'Acidic Slime');
      expect(row.values['Condition'], 'Near Mint');
      expect(row.values['Language'], 'English');
      expect(row.values.containsKey('Tradelist Count'), isTrue);
      expect(row.values.containsKey('Edition'), isFalse, reason: 'that file had no Edition column');
      expect(row.errorColumns, {'Count'});
      expect(row.reason, "Deckbox refused this row's count");
    });

    test("a refusal of the push's own file names the right column and matches what was sent", () {
      final sent = DeckboxImportFile.rowFor(_add(conditionCode: 3)).fields!;
      // Deckbox echoes the push's header, Scryfall ID dropped, and marks the cell.
      final cols = [for (final h in DeckboxImportFile.header) if (h != 'Scryfall ID') h];
      String cell(String h) => '<td class=\\"${h == 'Condition' ? 'error' : ''}\\">${sent[h] ?? ''}</td>';
      final html = '<table><tr>${cols.map((h) => '<th>$h</th>').join()}</tr>'
          '<tr>${cols.map(cell).join()}</tr></table>';
      final reply = "__.hide('#loading_import_list'); Element.update('file_check_results', \"$html\");";

      final row = (ImportReply.read(reply) as ImportRefused).rows.single;
      expect(row.errorColumns, {'Condition'});
      expect(row.reason, "Deckbox refused this row's condition");
      expect(row.echoKey, DeckboxImportFile.echoKey(sent), reason: 'matched exactly, no name fallback');
    });

    test('anything else is not taken for success', () {
      expect(ImportReply.read("window.location.href = '/accounts/login';"), isA<ImportUnknown>());
      expect(ImportReply.read(''), isA<ImportUnknown>());
    });
  });
}
