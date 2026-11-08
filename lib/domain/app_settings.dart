enum ConnectionAutomation { askBeforeSharing, manualOnly }

enum WindowsCloseBehavior { ask, minimizeToTray, exit }

class AppSettings {
  const AppSettings({
    this.backgroundMonitoring = true,
    this.notificationsEnabled = true,
    this.startMonitoringOnLaunch = true,
    this.idleTimeoutMinutes = 10,
    this.connectionAutomation = ConnectionAutomation.askBeforeSharing,
    this.windowsCloseBehavior = WindowsCloseBehavior.ask,
  });

  final bool backgroundMonitoring;
  final bool notificationsEnabled;
  final bool startMonitoringOnLaunch;
  final int idleTimeoutMinutes;
  final ConnectionAutomation connectionAutomation;
  final WindowsCloseBehavior windowsCloseBehavior;
  static const idleTimeoutOptions = [5, 10, 15, 30, 60];

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.backgroundMonitoring == backgroundMonitoring &&
      other.notificationsEnabled == notificationsEnabled &&
      other.startMonitoringOnLaunch == startMonitoringOnLaunch &&
      other.idleTimeoutMinutes == idleTimeoutMinutes &&
      other.connectionAutomation == connectionAutomation &&
      other.windowsCloseBehavior == windowsCloseBehavior;

  @override
  int get hashCode => Object.hash(
    backgroundMonitoring,
    notificationsEnabled,
    startMonitoringOnLaunch,
    idleTimeoutMinutes,
    connectionAutomation,
    windowsCloseBehavior,
  );

  AppSettings copyWith({
    bool? backgroundMonitoring,
    bool? notificationsEnabled,
    bool? startMonitoringOnLaunch,
    int? idleTimeoutMinutes,
    ConnectionAutomation? connectionAutomation,
    WindowsCloseBehavior? windowsCloseBehavior,
  }) => AppSettings(
    backgroundMonitoring: backgroundMonitoring ?? this.backgroundMonitoring,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    startMonitoringOnLaunch:
        startMonitoringOnLaunch ?? this.startMonitoringOnLaunch,
    idleTimeoutMinutes: idleTimeoutMinutes ?? this.idleTimeoutMinutes,
    connectionAutomation: connectionAutomation ?? this.connectionAutomation,
    windowsCloseBehavior: windowsCloseBehavior ?? this.windowsCloseBehavior,
  );
}
