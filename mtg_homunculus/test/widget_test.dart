import 'package:flutter_test/flutter_test.dart';
import 'package:mtg_homunculus/main.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const MtgHomunculusApp());
    expect(find.text('MtgHomunculus'), findsOneWidget);
  });
}
