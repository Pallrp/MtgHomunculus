import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtg_homunculus/features/card_lookup/data/collection_database.dart';
import 'package:mtg_homunculus/features/card_lookup/models/scan_defaults.dart';
import 'package:mtg_homunculus/features/card_lookup/widgets/attribute_chips.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    int finish = Finish.nonfoil,
    String language = 'en',
    int condition = Condition.nearMint,
    ScanDefaults defaults = const ScanDefaults(),
    bool deviationsOnly = false,
  }) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AttributeChips(
            finish: finish,
            language: language,
            condition: condition,
            defaults: defaults,
            deviationsOnly: deviationsOnly,
          ),
        ),
      ));

  /// The decoration of the chip carrying [label].
  BoxDecoration decorationOf(WidgetTester tester, String label) {
    final container = tester.widget<Container>(
      find.ancestor(of: find.text(label), matching: find.byType(Container)).first,
    );
    return container.decoration! as BoxDecoration;
  }

  group('deviation-coded: finish and language', () {
    testWidgets('matching the default is muted', (tester) async {
      await pump(tester);
      expect(decorationOf(tester, 'NONFOIL').gradient, isNull);
      expect(decorationOf(tester, 'EN').gradient, isNull);
    });

    testWidgets('foil is the one gradient in the list', (tester) async {
      await pump(tester, finish: Finish.foil);
      expect(decorationOf(tester, 'FOIL').gradient, isNotNull);
    });

    testWidgets('a foil default makes NONFOIL the notable chip', (tester) async {
      // The point of deviation-coding: what stands out is what is unusual *for
      // this user*, not a fixed idea of which finish is special.
      await pump(
        tester,
        finish: Finish.nonfoil,
        defaults: const ScanDefaults(finish: Finish.foil),
      );
      final plain = decorationOf(tester, 'NONFOIL');
      await pump(tester, finish: Finish.nonfoil);
      final muted = decorationOf(tester, 'NONFOIL');
      expect(plain.color, isNot(muted.color));
    });

    testWidgets('a non-default language is notable', (tester) async {
      await pump(tester, language: 'ja');
      final ja = decorationOf(tester, 'JA');
      await pump(tester);
      expect(ja.color, isNot(decorationOf(tester, 'EN').color));
    });

    testWidgets('a Japanese default makes EN the notable one', (tester) async {
      await pump(
        tester,
        language: 'en',
        defaults: const ScanDefaults(language: 'ja'),
      );
      final en = decorationOf(tester, 'EN');
      await pump(tester);
      expect(en.color, isNot(decorationOf(tester, 'EN').color));
    });
  });

  group('severity-coded: condition', () {
    testWidgets('warms as the card gets worse', (tester) async {
      final shades = <int, Color?>{};
      for (final c in Condition.all) {
        await pump(tester, condition: c);
        shades[c] = decorationOf(tester, Condition.label(c)).color;
      }
      // Four distinct damaged states, none of them sharing a colour.
      final damaged = [
        for (final c in Condition.all)
          if (c != Condition.nearMint) shades[c],
      ];
      expect(damaged.toSet(), hasLength(damaged.length));
    });

    testWidgets('does NOT follow the user default', (tester) async {
      // The rule that is easy to get backwards. A user whose cards are mostly
      // played must not see NM painted as the notable chip.
      await pump(tester, condition: Condition.nearMint);
      final nmNormally = decorationOf(tester, 'NM').color;

      await pump(
        tester,
        condition: Condition.nearMint,
        defaults: const ScanDefaults(condition: Condition.lightlyPlayed),
      );
      expect(decorationOf(tester, 'NM').color, nmNormally);
    });

    testWidgets('is shown even when only deviations are wanted', (tester) async {
      // NM is information, not an absence of it.
      await pump(tester, deviationsOnly: true);
      expect(find.text('NM'), findsOneWidget);
      expect(find.text('NONFOIL'), findsNothing);
      expect(find.text('EN'), findsNothing);
    });
  });

  group('deviationsOnly', () {
    testWidgets('keeps the chips that differ', (tester) async {
      await pump(
        tester,
        finish: Finish.foil,
        language: 'ja',
        deviationsOnly: true,
      );
      expect(find.text('FOIL'), findsOneWidget);
      expect(find.text('JA'), findsOneWidget);
    });
  });

  group('ScanDefaults.finishFor', () {
    test('keeps the default when the printing has it', () {
      const d = ScanDefaults();
      expect(d.finishFor(Finish.nonfoil | Finish.foil), Finish.nonfoil);
    });

    test('falls back to what the printing actually came in', () {
      // Storing a finish a card was never printed in produces an entry that
      // matches nothing real.
      const d = ScanDefaults();
      expect(d.finishFor(Finish.foil), Finish.foil);
    });

    test('a foil default falls back for a nonfoil-only printing', () {
      const d = ScanDefaults(finish: Finish.foil);
      expect(d.finishFor(Finish.nonfoil), Finish.nonfoil);
    });

    test('an unknown finish set leaves the default alone', () {
      const d = ScanDefaults();
      expect(d.finishFor(0), Finish.nonfoil);
    });
  });
}
