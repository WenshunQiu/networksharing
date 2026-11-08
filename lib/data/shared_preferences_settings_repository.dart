import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/app_settings.dart';
import '../features/settings/settings_repository.dart';

class SharedPreferencesSettingsRepository implements SettingsRepository {
  SharedPreferencesSettingsRepository(this._preferences);
  final SharedPreferencesAsync _preferences;
  static const storageKey = 'networksharing.settings';

  @override
  Future<AppSettings> load() async {
    final source = await _preferences.getString(storageKey);
    if (source == null) return const AppSettings();
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic> || decoded['version'] != 1) {
      throw const FormatException('Invalid or unsupported settings version');
    }
    final automation = ConnectionAutomation.values.firstWhere(
      (value) => value.name == decoded['connectionAutomation'],
      orElse: () => ConnectionAutomation.askBeforeSharing,
    );
    final idle = decoded['idleTimeoutMinutes'];
    return AppSettings(
      backgroundMonitoring: decoded['backgroundMonitoring'] is bool
          ? decoded['backgroundMonitoring'] as bool
          : true,
      notificationsEnabled: decoded['notificationsEnabled'] is bool
          ? decoded['notificationsEnabled'] as bool
          : true,
      startMonitoringOnLaunch: decoded['startMonitoringOnLaunch'] is bool
          ? decoded['startMonitoringOnLaunch'] as bool
          : true,
      idleTimeoutMinutes:
          idle is int && AppSettings.idleTimeoutOptions.contains(idle)
          ? idle
          : 10,
      connectionAutomation: automation,
    );
  }

  @override
  Future<void> save(AppSettings settings) async {
    if (!AppSettings.idleTimeoutOptions.contains(settings.idleTimeoutMinutes)) {
      throw ArgumentError.value(
        settings.idleTimeoutMinutes,
        'idleTimeoutMinutes',
      );
    }
    await _preferences.setString(
      storageKey,
      jsonEncode({
        'version': 1,
        'backgroundMonitoring': settings.backgroundMonitoring,
        'notificationsEnabled': settings.notificationsEnabled,
        'startMonitoringOnLaunch': settings.startMonitoringOnLaunch,
        'idleTimeoutMinutes': settings.idleTimeoutMinutes,
        'connectionAutomation': settings.connectionAutomation.name,
      }),
    );
  }
}
