import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mtg_homunculus/main.dart';
import 'package:mtg_homunculus/features/settings/services/settings_service.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final loaded = await SettingsService.load();
    await tester.pumpWidget(MtgHomunculusApp(
      service: loaded.service,
      app:     loaded.app,
      gt:      loaded.gt,
    ));
    expect(find.byType(MtgHomunculusApp), findsOneWidget);
  });
}
