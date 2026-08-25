import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mtg_homunculus/features/card_lookup/data/bulk_importer.dart';
import 'package:mtg_homunculus/features/card_lookup/data/cards_database.dart';

/// A real Scryfall card object, trimmed to the fields the importer reads.
Map<String, dynamic> card([Map<String, dynamic> overrides = const {}]) => {
      'id': '76ac5b70-47db-4cdb-91e7-e5c18c42e516',
      'oracle_id': '08c7db90-c0cf-4482-b7ee-bb033e5996d2',
      'illustration_id': '1339de69-bb3d-4925-a3c3-fd44da310958',
      'name': 'Colossal Dreadmaw',
      'set': 'xln',
      'set_name': 'Ixalan',
      'set_type': 'expansion',
      'collector_number': '180',
      'lang': 'en',
      'rarity': 'common',
      'released_at': '2017-09-29',
      'cmc': 6.0,
      'colors': ['G'],
      'color_identity': ['G'],
      'layout': 'normal',
      'full_art': false,
      'digital': false,
      'image_status': 'highres_scan',
      'image_updated_at': '2024-11-13T21:04:15.000+00:00',
      'finishes': ['nonfoil', 'foil'],
      ...overrides,
    };

void main() {
  late Map<String, CardSet> sets;
  setUp(() => sets = {});

  ({CardsCompanion? row, Map<String, CardSet> sets}) extract(
      [Map<String, dynamic> overrides = const {}]) {
    final row = BulkImporter.extractForTest(jsonEncode(card(overrides)), sets);
    return (row: row, sets: sets);
  }

  group('field mapping', () {
    test('pulls the identifying fields through unchanged', () {
      final r = extract().row!;
      expect(r.id.value, '76ac5b70-47db-4cdb-91e7-e5c18c42e516');
      expect(r.name.value, 'Colossal Dreadmaw');
      expect(r.setCode.value, 'xln');
      expect(r.collectorNumber.value, '180');
      expect(r.oracleId.value, '08c7db90-c0cf-4482-b7ee-bb033e5996d2');
    });

    test('rarity maps to its enum', () {
      for (final (name, want) in [
        ('common', 0),
        ('uncommon', 1),
        ('rare', 2),
        ('mythic', 3),
        ('special', 4),
        ('bonus', 5),
      ]) {
        expect(extract({'rarity': name}).row!.rarity.value, want,
            reason: name);
      }
      expect(extract({'rarity': 'nonsense'}).row!.rarity.value, isNull);
    });

    test('finishes become a bitmask', () {
      expect(extract({'finishes': ['nonfoil']}).row!.finishes.value, 1);
      expect(extract({'finishes': ['foil']}).row!.finishes.value, 2);
      expect(extract({'finishes': ['nonfoil', 'foil']}).row!.finishes.value, 3);
      expect(extract({'finishes': ['etched']}).row!.finishes.value, 4);
      expect(
          extract({'finishes': ['nonfoil', 'foil', 'etched']}).row!.finishes.value,
          7);
      expect(extract({'finishes': <String>[]}).row!.finishes.value, 0);
    });

    test('image_status maps to its enum', () {
      expect(extract({'image_status': 'missing'}).row!.imageStatus.value, 0);
      expect(extract({'image_status': 'placeholder'}).row!.imageStatus.value, 1);
      expect(extract({'image_status': 'lowres'}).row!.imageStatus.value, 2);
      expect(extract({'image_status': 'highres_scan'}).row!.imageStatus.value, 3);
    });

    test('colours join, and colourless is empty rather than null', () {
      expect(extract({'colors': ['B', 'R']}).row!.colors.value, 'BR');
      expect(extract({'colors': <String>[]}).row!.colors.value, '');
      expect(extract({'colors': null}).row!.colors.value, isNull);
    });

    test('dates become unix seconds', () {
      final r = extract().row!;
      expect(r.releasedAt.value,
          DateTime.parse('2017-09-29').millisecondsSinceEpoch ~/ 1000);
      expect(r.imageUpdatedAt.value, isNotNull);
      expect(extract({'released_at': null}).row!.releasedAt.value, isNull);
      expect(extract({'released_at': ''}).row!.releasedAt.value, isNull);
    });

    test('a two-faced card is marked as having a back', () {
      expect(extract().row!.hasBack.value, isFalse);
      expect(
        extract({
          'card_faces': [
            {'name': 'Front'},
            {'name': 'Back'},
          ]
        }).row!.hasBack.value,
        isTrue,
      );
    });
  });

  group('rejection', () {
    test('digital-only printings are skipped — nothing physical to scan', () {
      expect(extract({'digital': true}).row, isNull);
    });

    test('a card missing an identifying field is skipped, not half-imported', () {
      for (final missing in [
        'id',
        'name',
        'set',
        'oracle_id',
        'collector_number',
      ]) {
        expect(extract({missing: null}).row, isNull, reason: 'missing $missing');
      }
    });

    test('non-card lines are skipped without throwing', () {
      expect(BulkImporter.extractForTest('[', sets), isNull);
      expect(BulkImporter.extractForTest(']', sets), isNull);
      expect(BulkImporter.extractForTest('', sets), isNull);
      expect(BulkImporter.extractForTest('{not json', sets), isNull);
    });
  });

  group('sets are derived from the card stream', () {
    test('a set is captured the first time one of its cards appears', () {
      final r = extract();
      expect(r.sets, hasLength(1));
      final s = r.sets['xln']!;
      expect(s.code, 'xln');
      expect(s.name, 'Ixalan');
      expect(s.setType, 'expansion');
      expect(s.releasedAt, isNotNull);
    });

    test('a second card from the same set does not duplicate it', () {
      extract();
      extract({'id': 'other', 'collector_number': '181'});
      expect(sets, hasLength(1));
    });

    test('a set with no name falls back to its code', () {
      final r = extract({'set': 'zzz', 'set_name': null});
      expect(r.sets['zzz']!.name, 'zzz');
    });
  });

  group('progress', () {
    test('fraction is null without a denominator, so the UI can go indeterminate',
        () {
      expect(const ImportProgress(ImportStep.indexing).fraction, isNull);
      expect(
          const ImportProgress(ImportStep.inserting, current: 50, total: 200)
              .fraction,
          0.25);
    });

    test('fraction cannot exceed 1 when an estimate is wrong', () {
      expect(
          const ImportProgress(ImportStep.inserting, current: 300, total: 200)
              .fraction,
          1.0);
    });
  });
}
