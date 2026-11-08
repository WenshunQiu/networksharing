enum ConnectionAutomation { askBeforeSharing, manualOnly }

class AppSettings {
  const AppSettings({
    this.backgroundMonitoring = true,
    this.notificationsEnabled = true,
    this.startMonitoringOnLaunch = true,
    this.idleTimeoutMinutes = 10,
    this.connectionAutomation = ConnectionAutomation.askBeforeSharing,
  });

  final bool backgroundMonitoring;
  final bool notificationsEnabled;
  final bool startMonitoringOnLaunch;
  final int idleTimeoutMinutes;
  final ConnectionAutomation connectionAutomation;
  static const idleTimeoutOptions = [5, 10, 15, 30, 60];

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.backgroundMonitoring == backgroundMonitoring &&
      other.notificationsEnabled == notificationsEnabled &&
      other.startMonitoringOnLaunch == startMonitoringOnLaunch &&
      other.idleTimeoutMinutes == idleTimeoutMinutes &&
      other.connectionAutomation == connectionAutomation;

  @override
  int get hashCode => Object.hash(
    backgroundMonitoring,
    notificationsEnabled,
    startMonitoringOnLaunch,
    idleTimeoutMinutes,
    connectionAutomation,
  );

  AppSettings copyWith({
    bool? backgroundMonitoring,
    bool? notificationsEnabled,
    bool? startMonitoringOnLaunch,
    int? idleTimeoutMinutes,
    ConnectionAutomation? connectionAutomation,
  }) => AppSettings(
    backgroundMonitoring: backgroundMonitoring ?? this.backgroundMonitoring,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    startMonitoringOnLaunch:
        startMonitoringOnLaunch ?? this.startMonitoringOnLaunch,
    idleTimeoutMinutes: idleTimeoutMinutes ?? this.idleTimeoutMinutes,
    connectionAutomation: connectionAutomation ?? this.connectionAutomation,
  );
}
