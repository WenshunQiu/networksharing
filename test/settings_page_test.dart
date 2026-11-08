import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:networksharing/features/settings/settings_page.dart';
import 'package:networksharing/features/settings/settings_view_model.dart';

import 'settings_view_model_test.dart' show ControlledSettingsRepository;

void main() {
  for (final width in [320.0, 390.0, 1200.0]) {
    testWidgets('settings can be edited at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = ControlledSettingsRepository();
      final vm = SettingsViewModel(repository);
      await tester.pumpWidget(
        FluentApp(
          home: ScaffoldPage(content: SettingsPage(viewModel: vm)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ToggleSwitch).first);
      await tester.pumpAndSettle();
      expect(repository.stored.backgroundMonitoring, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      vm.dispose();
    });
  }
}
