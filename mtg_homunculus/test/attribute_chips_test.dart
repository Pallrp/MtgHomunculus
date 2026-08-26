import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtg_homunculus/features/card_lookup/data/collection_database.dart';
import 'package:mtg_homunculus/features/card_lookup/models/scan_defaults.dart';
import 'package:mtg_homunculus/features/card_lookup/theme/picker_tokens.dart';
import 'package:mtg_homunculus/features/card_lookup/widgets/attribute_chips.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    int finish = Finish.nonfoil,
    String language = 'en',
    int condition = Condition.nearMint,
    ScanDefaults defaults = const ScanDefaults(),
  }) =>
      tester.pumpWidget(MaterialApp(
        theme: ThemeData(extensions: const [PickerTokens.light]),
        home: Scaffold(
          body: AttributeChips(
            finish: finish,
            language: language,
            condition: condition,
            defaults: defaults,
          ),
        ),
      ));

  BoxDecoration decorationOf(WidgetTester tester, String label) {
    final container = tester.widget<Container>(
      find.ancestor(of: find.text(label), matching: find.byType(Container)).first,
    );
    return container.decoration! as BoxDecoration;
  }

  group('all three, always', () {
    testWidgets('every attribute is shown even at defaults', (tester) async {
      // Row height is thumbnail-driven, so chips ride along free — hiding the
      // ones matching your defaults saves nothing and costs legibility.
      await pump(tester);
      expect(find.text('NORMAL'), findsOneWidget);
      expect(find.text('EN'), findsOneWidget);
      expect(find.text('NM'), findsOneWidget);
    });

    testWidgets('nonfoil is labelled NORMAL, as a shop would', (tester) async {
      await pump(tester);
      expect(find.text('NONFOIL'), findsNothing);
    });
  });

  group('deviation-coded: finish and language', () {
    testWidgets('matching the default recedes', (tester) async {
      await pump(tester);
      const t = PickerTokens.light;
      expect(decorationOf(tester, 'NORMAL').color, t.surface2);
      expect(decorationOf(tester, 'EN').color, t.surface2);
    });

    testWidgets('differing takes the accent', (tester) async {
      await pump(tester, language: 'ja');
      expect(decorationOf(tester, 'JA').color, PickerTokens.light.accentSoft);
    });

    testWidgets('foil is the one gradient in the list', (tester) async {
      await pump(tester, finish: Finish.foil);
      expect(decorationOf(tester, 'FOIL').gradient, isNotNull);
    });

    testWidgets('a foil default makes NORMAL the notable chip', (tester) async {
      // The point of deviation-coding: what stands out is what is unusual *for
      // this user*, not a fixed idea of which finish is special.
      await pump(
        tester,
        finish: Finish.nonfoil,
        defaults: const ScanDefaults(finish: Finish.foil),
      );
      expect(decorationOf(tester, 'NORMAL').color,
          PickerTokens.light.accentSoft);
    });

    testWidgets('a Japanese default makes EN the notable one', (tester) async {
      await pump(
        tester,
        language: 'en',
        defaults: const ScanDefaults(language: 'ja'),
      );
      expect(decorationOf(tester, 'EN').color, PickerTokens.light.accentSoft);
    });
  });

  group('severity-coded: condition', () {
    testWidgets('each step has its own colour from the artifact ramp',
        (tester) async {
      const t = PickerTokens.light;
      final expected = {
        Condition.nearMint: t.surface2,
        Condition.lightlyPlayed: t.condLpBg,
        Condition.moderatelyPlayed: t.condMpBg,
        Condition.heavilyPlayed: t.condHpBg,
        Condition.damaged: t.condDmBg,
      };
      for (final c in Condition.all) {
        await pump(tester, condition: c);
        expect(decorationOf(tester, Condition.label(c)).color, expected[c],
            reason: Condition.label(c));
      }
    });

    testWidgets('does NOT follow the user default', (tester) async {
      // The rule that is easy to get backwards. A user whose cards are mostly
      // played must not see NM painted as the notable chip.
      await pump(tester, condition: Condition.nearMint);
      final normally = decorationOf(tester, 'NM').color;

      await pump(
        tester,
        condition: Condition.nearMint,
        defaults: const ScanDefaults(condition: Condition.lightlyPlayed),
      );
      expect(decorationOf(tester, 'NM').color, normally);
    });

    testWidgets('never takes the accent, however unusual it is',
        (tester) async {
      // Severity and deviation must not blur: LP is warm, never accent-green.
      await pump(tester, condition: Condition.lightlyPlayed);
      expect(decorationOf(tester, 'LP').color,
          isNot(PickerTokens.light.accentSoft));
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
