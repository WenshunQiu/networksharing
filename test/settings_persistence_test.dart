import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:networksharing/data/shared_preferences_settings_repository.dart';
import 'package:networksharing/domain/app_settings.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('invalid documents stay preserved on read failure', () async {
    final preferences = SharedPreferencesAsync();
    final repository = SharedPreferencesSettingsRepository(preferences);
    for (final source in ['invalid-json', '[]', '{"version":99}']) {
      await preferences.setString(
        SharedPreferencesSettingsRepository.storageKey,
        source,
      );
      await expectLater(repository.load(), throwsFormatException);
      expect(
        await preferences.getString(
          SharedPreferencesSettingsRepository.storageKey,
        ),
        source,
      );
    }
  });

  test('loads defaults and restores saved settings', () async {
    final repository = SharedPreferencesSettingsRepository(
      SharedPreferencesAsync(),
    );

    expect(await repository.load(), const AppSettings());

    const saved = AppSettings(
      backgroundMonitoring: false,
      notificationsEnabled: false,
      startMonitoringOnLaunch: false,
      idleTimeoutMinutes: 30,
      connectionAutomation: ConnectionAutomation.manualOnly,
    );
    await repository.save(saved);
    final reopened = SharedPreferencesSettingsRepository(
      SharedPreferencesAsync(),
    );
    expect(await reopened.load(), saved);
  });

  test('falls back from unknown persisted values', () async {
    await SharedPreferencesAsync().setString(
      SharedPreferencesSettingsRepository.storageKey,
      '{"version":1,"idleTimeoutMinutes":7,"connectionAutomation":"futureMode"}',
    );
    final repository = SharedPreferencesSettingsRepository(
      SharedPreferencesAsync(),
    );
    final settings = await repository.load();

    expect(settings.idleTimeoutMinutes, 10);
    expect(
      settings.connectionAutomation,
      ConnectionAutomation.askBeforeSharing,
    );
  });
}
