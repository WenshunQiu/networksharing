import 'package:fluent_ui/fluent_ui.dart';

import 'dart:io';

import 'package:share_plus/share_plus.dart';

import 'dart:typed_data';

import '../../data/app_logger.dart';

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
                  const SizedBox(height: 28),
                  const Divider(),
                  Text(
                    '诊断日志',
                    style: FluentTheme.of(context).typography.subtitle,
                  ),
                  const SizedBox(height: 8),
                  FutureBuilder<String?>(
                    future: AppLogger.instance.filePath,
                    builder: (context, snapshot) => SelectableText(
                      snapshot.data ?? '日志路径尚未初始化',
                      key: const ValueKey('diagnostic-log-path'),
                    ),
                  ),
                  const Text('日志位于应用私有目录，卸载应用会清除。可导出文件并附在问题反馈中。'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Button(
                        onPressed: () async {
                          final path = await AppLogger.instance.filePath;
                          if (!context.mounted) return;
                          await showDialog<void>(
                            context: context,
                            builder: (context) => ContentDialog(
                              title: const Text('日志文件位置'),
                              content: SelectableText(path ?? '当前无法创建日志文件'),
                              actions: [
                                Button(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('关闭'),
                                ),
                              ],
                            ),
                          );
                        },
                        child: const Text('显示日志路径'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () async {
                          try {
                            await AppLogger.instance.flush();
                            final path = await AppLogger.instance.filePath;
                            if (path == null) {
                              throw StateError('log_path_unavailable');
                            }
                            final current = File(path);
                            final backup = File('$path.1');
                            final contents = [
                              if (await backup.exists())
                                await backup.readAsBytes(),
                              if (await current.exists())
                                await current.readAsBytes(),
                            ].expand((part) => part).toList(growable: false);
                            await SharePlus.instance.share(
                              ShareParams(
                                files: [
                                  XFile.fromData(
                                    Uint8List.fromList(contents),
                                    name: 'networksharing.log',
                                    mimeType: 'text/plain',
                                  ),
                                ],
                                fileNameOverrides: const ['networksharing.log'],
                                title: 'NetworkSharing 诊断日志',
                              ),
                            );
                          } catch (error) {
                            AppLogger.instance.error(
                              'ui',
                              'logs.export_failed',
                              {'errorType': error.runtimeType.toString()},
                            );
                            if (!context.mounted) return;
                            await showDialog<void>(
                              context: context,
                              builder: (context) => ContentDialog(
                                title: const Text('日志导出失败'),
                                content: const Text(
                                  '请使用“显示日志路径”查看文件位置，或稍后重试导出。',
                                ),
                                actions: [
                                  Button(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('关闭'),
                                  ),
                                ],
                              ),
                            );
                          }
                        },
                        child: const Text('导出日志'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}
