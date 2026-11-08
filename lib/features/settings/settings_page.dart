import 'package:fluent_ui/fluent_ui.dart';

import '../../domain/app_settings.dart';
import 'settings_view_model.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({required this.viewModel, super.key});
  final SettingsViewModel viewModel;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: viewModel,
    builder: (context, _) {
      final vm = viewModel;
      final settings = vm.settings;
      final enabled = !vm.loading && !vm.saving && vm.error == null;
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('设置', style: FluentTheme.of(context).typography.title),
                const SizedBox(height: 16),
                const InfoBar(
                  title: Text('偏好自动保存在本机'),
                  content: Text('后台服务、系统通知和热点控制尚未接入。以下设置将用于后续功能；开启偏好不会授予系统权限。'),
                ),
                if (vm.error != null) ...[
                  const SizedBox(height: 16),
                  InfoBar(
                    title: Text(vm.error!),
                    severity: InfoBarSeverity.error,
                  ),
                  Button(
                    onPressed: vm.saving ? null : vm.load,
                    child: const Text('重新读取设置'),
                  ),
                ],
                if (vm.loading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: ProgressRing()),
                  )
                else ...[
                  const SizedBox(height: 24),
                  ToggleSwitch(
                    checked: settings.backgroundMonitoring,
                    content: const Text('允许后台监测'),
                    onChanged: enabled
                        ? (v) => vm.update(
                            settings.copyWith(backgroundMonitoring: v),
                          )
                        : null,
                  ),
                  const SizedBox(height: 20),
                  ToggleSwitch(
                    checked: settings.notificationsEnabled,
                    content: const Text('允许共享请求和连接状态通知'),
                    onChanged: enabled
                        ? (v) => vm.update(
                            settings.copyWith(notificationsEnabled: v),
                          )
                        : null,
                  ),
                  const SizedBox(height: 20),
                  ToggleSwitch(
                    checked: settings.startMonitoringOnLaunch,
                    content: const Text('应用启动时开始监测'),
                    onChanged: enabled
                        ? (v) => vm.update(
                            settings.copyWith(startMonitoringOnLaunch: v),
                          )
                        : null,
                  ),
                  const SizedBox(height: 24),
                  const Text('热点无客户端时自动关闭'),
                  const SizedBox(height: 8),
                  ComboBox<int>(
                    value: settings.idleTimeoutMinutes,
                    items: AppSettings.idleTimeoutOptions
                        .map(
                          (v) => ComboBoxItem(value: v, child: Text('$v 分钟')),
                        )
                        .toList(),
                    onChanged: enabled
                        ? (v) {
                            if (v != null) {
                              vm.update(
                                settings.copyWith(idleTimeoutMinutes: v),
                              );
                            }
                          }
                        : null,
                  ),
                  const SizedBox(height: 24),
                  const Text('共享请求方式'),
                  const SizedBox(height: 8),
                  ComboBox<ConnectionAutomation>(
                    value: settings.connectionAutomation,
                    items: const [
                      ComboBoxItem(
                        value: ConnectionAutomation.askBeforeSharing,
                        child: Text('每次请求均确认'),
                      ),
                      ComboBoxItem(
                        value: ConnectionAutomation.manualOnly,
                        child: Text('仅手动请求'),
                      ),
                    ],
                    onChanged: enabled
                        ? (v) {
                            if (v != null) {
                              vm.update(
                                settings.copyWith(connectionAutomation: v),
                              );
                            }
                          }
                        : null,
                  ),
                  const SizedBox(height: 20),
                  Text(vm.saving ? '正在保存…' : '更改后自动保存'),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}
