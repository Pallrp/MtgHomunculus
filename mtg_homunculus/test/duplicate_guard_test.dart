import 'package:flutter_test/flutter_test.dart';
import 'package:mtg_homunculus/features/card_lookup/data/cards_database.dart';
import 'package:mtg_homunculus/features/card_lookup/services/card_identifier.dart';
import 'package:mtg_homunculus/features/card_lookup/services/duplicate_guard.dart';

/// A fingerprint stated directly, so each test says what the *scan produced*
/// rather than reconstructing it through the identifier.
ScanFingerprint fp(
  String printingId, {
  String name = 'Swamp',
  Set<String>? candidates,
}) =>
    ScanFingerprint(
      printingId: printingId,
      candidateIds: candidates ?? {printingId},
      name: name,
    );

Card card(String id, {String name = 'Swamp', String set = 'm21', String num = '267'}) =>
    Card(
      id: id,
      oracleId: 'oracle-1',
      name: name,
      setCode: set,
      collectorNumber: num,
      lang: 'en',
      fullArt: false,
      hasBack: false,
      imageStatus: 3,
      finishes: 1,
    );

void main() {
  late DuplicateGuard guard;
  setUp(() => guard = DuplicateGuard());

  group('first scan', () {
    test('nothing is a duplicate before anything has been added', () {
      expect(guard.isDuplicate(fp('a')), isFalse);
    });
  });

  group('the printings considered', () {
    test('the same card held in frame is rejected after the first add', () {
      // The loop fires 2-3x/second; without this one card becomes a dozen.
      guard.remember(fp('a'));
      expect(guard.isDuplicate(fp('a')), isTrue);
      expect(guard.isDuplicate(fp('a')), isTrue, reason: 'stays rejected');
    });

    test('a different card is added', () {
      guard.remember(fp('a'));
      expect(guard.isDuplicate(fp('b', name: 'Island')), isFalse);
    });

    test('the pick from Choose Version is not re-prompted next frame', () {
      // The regression this exists for. Nine identical-art Swamps: the user
      // picks the fifth, and the next frame's best candidate is the first
      // again. Comparing only the chosen printing would call that a new card
      // and re-open the picker every few hundred milliseconds.
      final all = {'s1', 's2', 's3', 's4', 's5'};
      guard.remember(fp('s5', candidates: all));
      expect(guard.isDuplicate(fp('s1', candidates: all)), isTrue);
    });

    test('a candidate dropping out between frames is still the same card', () {
      guard.remember(fp('s1', candidates: {'s1', 's2', 's3'}));
      expect(guard.isDuplicate(fp('s2', candidates: {'s2', 's3'})), isTrue);
    });

    test('skipping is remembered, so the picker does not reopen', () {
      // "Skip" has to mean "keep scanning", not "ask me again immediately".
      guard.remember(fp('s1', candidates: {'s1', 's2'}));
      expect(guard.isDuplicate(fp('s1', candidates: {'s1', 's2'})), isTrue);
    });
  });

  group('the name backstop', () {
    test('disjoint candidates still read as the same card', () async {
      // dHash and the name search can return completely different candidates
      // for one physical card — art on one side, text on the other. They still
      // agree on what it is called.
      guard.remember(fp('a', candidates: {'a', 'b'}));
      expect(guard.isDuplicate(fp('x', candidates: {'x', 'y'})), isTrue);
    });

    test('a different card is still added', () {
      guard.remember(fp('a', name: 'Swamp'));
      expect(guard.isDuplicate(fp('b', name: 'Island')), isFalse);
    });

    test('an empty name cannot match itself into a duplicate', () {
      guard.remember(fp('a', name: ''));
      expect(guard.isDuplicate(fp('b', name: '')), isFalse);
    });
  });

  group('regression — the misread set code, 2026-08-26', () {
    test('a re-identified card does not re-prompt when its set misreads', () {
      // Measured on device. A Swamp was added from a 1-candidate hashAndOcr
      // match, then a later frame fell through to the name path and returned
      // four printings all at collector 267 — the set code was what failed.
      // The added printing is present in that list, so this is the same card;
      // the old precedence ladder let the misread set veto the match and
      // re-opened Choose Version on a card already in the list.
      guard.remember(fp('m21', name: 'Swamp', candidates: {'m21'}));

      final nextFrame = fp('iko',
          name: 'Swamp', candidates: {'iko', 'snc', 'm21', 'ltr'});

      expect(guard.isDuplicate(nextFrame), isTrue);
    });

    test('two printings of one card scanned in a row are rejected', () {
      // The behaviour the old rank 1 existed to prevent, now accepted
      // deliberately: same-art reprints share candidates and would be rejected
      // regardless, and adding a second printing goes through Add Version.
      guard.remember(fp('m21', name: 'Swamp', candidates: {'m21'}));
      expect(
        guard.isDuplicate(fp('lci', name: 'Swamp', candidates: {'lci'})),
        isTrue,
      );
    });
  });

  group('reset', () {
    test('a second copy scanned after leaving the camera is added', () {
      guard.remember(fp('a'));
      guard.reset();
      expect(guard.isDuplicate(fp('a')), isFalse);
    });
  });

  group('ScanFingerprint.of', () {
    test('records the user pick plus every candidate considered', () {
      final chosen = card('s5');
      final id = Identification(
        candidates: [card('s1'), card('s2'), chosen],
        via: IdentifiedVia.hash,
      );
      final f = ScanFingerprint.of(id, chosen);
      expect(f.printingId, 's5');
      expect(f.candidateIds, {'s1', 's2', 's5'});
      expect(f.name, 'Swamp');
    });

    test('the pick is included even when it is not among the candidates', () {
      // Choose Version can widen to every printing of the name, so the row the
      // user picks need not be one the scan originally offered.
      final chosen = card('other', name: 'Swamp');
      final id = Identification(
        candidates: [card('s1'), card('s2')],
        via: IdentifiedVia.hash,
      );
      expect(ScanFingerprint.of(id, chosen).candidateIds,
          {'s1', 's2', 'other'});
    });
  });
}
