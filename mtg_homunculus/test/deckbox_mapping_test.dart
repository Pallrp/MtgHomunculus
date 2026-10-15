import 'package:flutter_test/flutter_test.dart';
import 'package:mtg_homunculus/features/card_lookup/external/deckbox/deckbox_csv.dart';
import 'package:mtg_homunculus/features/card_lookup/external/deckbox/deckbox_mapping.dart';

/// Rows exactly as the test account's exports gave them (2026-10-15), with the
/// *Last Updated* and *Scryfall ID* columns the pull asks for.
const _inventory = r'''
Count,Tradelist Count,Name,Edition,Edition Code,Card Number,Condition,Language,Foil,Signed,Artist Proof,Altered Art,Misprint,Promo,Textless,Printing Id,Printing Note,Tags,My Price,Last Updated,Scryfall ID
1,1,Canopy Baloth,Zendikar Rising,znr,304,Near Mint,Japanese,,,,,,,,52892,Showcase,"",$0.00,2026-10-14 13:21:49 UTC,d52e90d3-d356-4b23-8f5c-a4004b20394c
1,0,"Edgar, Moonlit Sovereign",Reality Fracture,fra,257,Near Mint,English,foil,,,,,,,114503,,"",$0.00,2026-10-14 13:16:51 UTC,dad6afc9-8505-4cdd-bf79-e9ba4670f2bb
1,0,Aeromoeba,Modern Horizons 2 Etched,mh2_e,389,Near Mint,English,,,,,,,,99999,,"",$0.00,2026-10-15 13:33:44 UTC,
1,1,Way of the Warlord,Reality Fracture,fra,255,Heavily Played,English,,,,,,,,114501,,"",$0.00,2026-10-14 13:18:47 UTC,6d86e410-20c4-4248-96bf-5780ece6274a
''';

const _wishlist = '''
Count,Name,Edition,Edition Code,Card Number,Condition,Language,Foil,Signed,Artist Proof,Altered Art,Misprint,Promo,Textless,Printing Id,Printing Note,Last Updated,Scryfall ID
1,"Gisela, Blade of Goldnight","","",,,,,,,,,,,,,2026-10-14 13:19:08 UTC,7208fcb8-83e6-44ce-af9a-ca1566825018
1,Snake Basket,"","",,Played,,,,,,,,,,,2026-10-14 13:20:30 UTC,bfda9a16-9cdb-494a-b662-ac24e3b89d0c
1,The Ur-Dragon,Commander 2017,c17,48,,,foil,,,,,,,36563,,2026-10-14 13:20:21 UTC,7e78b70b-0c67-4f14-8ad7-c9f8e3f59743
''';

List<DeckboxRow> _read(String csv) {
  final rows = DeckboxCsv.rows(csv);
  return [for (var i = 0; i < rows.length; i++) DeckboxMapping.read(rows[i], i)];
}

void main() {
  group('an ordinary row', () {
    final rows = _read(_inventory);

    test('takes its card from the Scryfall ID, its language from Deckbox', () {
      final canopy = rows[0];
      expect(canopy.cardId, 'd52e90d3-d356-4b23-8f5c-a4004b20394c');
      expect(canopy.cardRef, canopy.cardId);
      expect(canopy.languageCode, 'ja');
      expect(canopy.conditionCode, 0);
      expect(canopy.finish, DeckboxMapping.nonfoil);
      expect(canopy.tradeCount, 1);
      expect(canopy.anyPrinting, isFalse);
      expect(canopy.etchedLookup, isNull);
    });

    test('reads foil, and Heavily Played as HP', () {
      expect(rows[1].finish, DeckboxMapping.foil);
      expect(rows[3].conditionCode, 3);
    });

    test('parses Last Updated as UTC seconds', () {
      expect(rows[0].lastUpdated,
          DateTime.utc(2026, 10, 14, 13, 21, 49).millisecondsSinceEpoch ~/ 1000);
    });

    test('keeps its position in the export', () {
      expect(rows.map((r) => r.position), [0, 1, 2, 3]);
    });
  });

  group('an etched row', () {
    final aeromoeba = _read(_inventory)[2];

    test('has no Scryfall ID, so it asks to be looked up in its base set', () {
      expect(aeromoeba.cardId, isNull);
      expect(aeromoeba.etchedLookup, (set: 'mh2', number: '389'));
      expect(aeromoeba.finish, DeckboxMapping.etched);
    });

    test('takes the printing the lookup found', () {
      final found = aeromoeba.withCard('25de0eb6-94f5-440f-8201-cc7dad2f0805');
      expect(found.cardId, '25de0eb6-94f5-440f-8201-cc7dad2f0805');
      expect(found.cardRef, found.cardId);
      expect(found.finish, DeckboxMapping.etched);
    });
  });

  group('a generic ("any printing") row', () {
    final rows = _read(_wishlist);

    test('has no card, only a stand-in reference', () {
      final gisela = rows[0];
      expect(gisela.anyPrinting, isTrue);
      expect(gisela.cardId, isNull, reason: 'the stand-in must never become its card');
      expect(gisela.cardRef, '7208fcb8-83e6-44ce-af9a-ca1566825018');
    });

    test('leaves unset what Deckbox leaves unset', () {
      final gisela = rows[0];
      expect(gisela.finish, isNull, reason: 'no foil on a generic row means "any", not nonfoil');
      expect(gisela.conditionCode, isNull);
      expect(gisela.languageCode, isNull);
    });

    test('keeps what it does set', () {
      expect(rows[1].conditionCode, 2, reason: 'Played is MP');
    });

    test('is told apart from a wishlist row that names its printing', () {
      final urDragon = rows[2];
      expect(urDragon.anyPrinting, isFalse);
      expect(urDragon.cardId, '7e78b70b-0c67-4f14-8ad7-c9f8e3f59743');
      expect(urDragon.finish, DeckboxMapping.foil);
    });
  });

  group('identity', () {
    test('two copies of one printing differing by condition are different rows', () {
      final a = DeckboxMapping.identityOf({'Name': 'Way of the Warlord', 'Printing Id': '114501', 'Condition': 'Near Mint', 'Foil': 'foil'});
      final b = DeckboxMapping.identityOf({'Name': 'Way of the Warlord', 'Printing Id': '114501', 'Condition': 'Heavily Played'});
      expect(a, isNot(b));
    });

    test('a set flag is part of it', () {
      final plain = DeckboxMapping.read({'Count': '1', 'Name': 'X', 'Printing Id': '1'}, 0);
      final signed = DeckboxMapping.read({'Count': '1', 'Name': 'X', 'Printing Id': '1', 'Signed': 'signed'}, 0);
      expect(signed.rowFlags, 'Signed');
      expect(signed.identityKey, isNot(plain.identityKey));
    });
  });

  group('the vocabulary', () {
    test('Mint shows as NM; Proxy has no app condition', () {
      expect(DeckboxMapping.conditions['Mint'], 0);
      expect(DeckboxMapping.conditions['Proxy'], isNull);
    });

    test('all eleven languages map, Chinese to zhs', () {
      expect(DeckboxMapping.languages, hasLength(11));
      expect(DeckboxMapping.languages['Chinese'], 'zhs');
      expect(DeckboxMapping.languages['Traditional Chinese'], 'zht');
    });

    test('a row with no count is a loud failure, not a skipped row', () {
      expect(() => DeckboxMapping.read({'Name': 'X'}, 4), throwsFormatException);
    });
  });
}
