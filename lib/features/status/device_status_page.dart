import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/connectivity.dart';
import 'connectivity_view_model.dart';
import '../bluetooth/bluetooth_view_model.dart';

class DeviceStatusPage extends StatelessWidget {
  const DeviceStatusPage({
    required this.viewModel,
    required this.bluetoothViewModel,
    super.key,
  });
  final ConnectivityViewModel viewModel;
  final BluetoothViewModel bluetoothViewModel;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([viewModel, bluetoothViewModel]),
    builder: (context, _) => SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('设备状态', style: FluentTheme.of(context).typography.title),
              const SizedBox(height: 20),
              Text('本机网络', style: FluentTheme.of(context).typography.subtitle),
              const SizedBox(height: 12),
              Text(
                viewModel.snapshot == null
                    ? '尚未检测'
                    : viewModel.snapshot!.state == ConnectivityState.online
                    ? '互联网可用'
                    : '无法确认网络可用性',
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: viewModel.checking ? null : viewModel.refresh,
                child: Text(viewModel.checking ? '正在检测…' : '检测网络'),
              ),
              const SizedBox(height: 12),
              const Text('点击后访问 Microsoft 连通性测试地址。单个地址不可达不能确定设备离线。目前尚未启动后台监测。'),
              const SizedBox(height: 24),
              Text('已配对设备', style: FluentTheme.of(context).typography.subtitle),
              const SizedBox(height: 12),
              _pairedDeviceTile(context),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _pairedDeviceTile(BuildContext context) {
    final bluetooth = bluetoothViewModel;
    final device = bluetooth.connectedDevice;
    final isWindows = defaultTargetPlatform == TargetPlatform.windows;
    if (bluetooth.applicationPaired) {
      return _DeviceTile(
        name: isWindows ? '已连接手机' : (device?.name ?? 'Windows 电脑'),
        status: '在线 · 应用配对成功',
        icon: FluentIcons.devices2,
        severity: InfoBarSeverity.success,
        onManagePermissions: _managePermissions,
      );
    }
    if (bluetooth.hasPersistedPairing) {
      return _DeviceTile(
        name: bluetooth.pairedDeviceName ?? '已配对设备',
        status: '离线 · 应用配对已保存',
        icon: FluentIcons.devices2,
        severity: InfoBarSeverity.info,
        onManagePermissions: _managePermissions,
      );
    }
    if (device != null) {
      return _DeviceTile(
        name: device.name,
        status: '在线 · 尚未完成应用配对',
        icon: FluentIcons.devices2,
        severity: InfoBarSeverity.warning,
        onManagePermissions: _managePermissions,
      );
    }
    return _DeviceTile(
      name: isWindows && bluetooth.advertising ? 'NetworkSharing' : '尚未配对设备',
      status: isWindows && bluetooth.advertising ? '等待设备连接' : '暂无在线设备',
      icon: FluentIcons.bluetooth,
      severity: InfoBarSeverity.info,
      onManagePermissions: _managePermissions,
    );
  }

  Future<void> _managePermissions() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      await const MethodChannel('networksharing/bluetooth')
          .invokeMethod<void>('openAppSettings');
    } else if (defaultTargetPlatform == TargetPlatform.windows) {
      await const MethodChannel('networksharing/bluetooth')
          .invokeMethod<void>('openBluetoothSettings');
    }
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.name,
    required this.status,
    required this.icon,
    required this.severity,
    required this.onManagePermissions,
  });

  final String name;
  final String status;
  final IconData icon;
  final InfoBarSeverity severity;
  final VoidCallback onManagePermissions;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: FluentTheme.of(context).resources.cardBackgroundFillColorDefault,
      border: Border.all(
        color: FluentTheme.of(context).resources.cardStrokeColorDefault,
      ),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      children: [
        Icon(icon, size: 24),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: FluentTheme.of(context).typography.bodyStrong),
              const SizedBox(height: 4),
              Text(status),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Button(
          onPressed: onManagePermissions,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(FluentIcons.lock, size: 14),
              SizedBox(width: 6),
              Text('管理权限'),
            ],
          ),
        ),
      ],
    ),
  );
}
