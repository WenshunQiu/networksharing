import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/connectivity.dart';
import 'connectivity_view_model.dart';
import '../bluetooth/bluetooth_view_model.dart';
import '../sharing/sharing_view_model.dart';

class DeviceStatusPage extends StatelessWidget {
  const DeviceStatusPage({
    required this.viewModel,
    required this.bluetoothViewModel,
    this.sharingViewModel,
    super.key,
  });
  final ConnectivityViewModel viewModel;
  final BluetoothViewModel bluetoothViewModel;
  final SharingViewModel? sharingViewModel;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      viewModel,
      bluetoothViewModel,
      sharingViewModel,
    ]),
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
                    : '未检测到网络连接',
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: viewModel.checking ? null : viewModel.refresh,
                child: Text(viewModel.checking ? '正在检测…' : '检测网络'),
              ),
              const SizedBox(height: 12),
              Text(
                viewModel.snapshot?.reachableHosts.isNotEmpty == true
                    ? '可达站点：${viewModel.snapshot!.reachableHosts.join('、')}'
                    : '自动检测百度和 Google 的 HTTPS 连通性。',
              ),
              const SizedBox(height: 24),
              Text('已配对设备', style: FluentTheme.of(context).typography.subtitle),
              const SizedBox(height: 12),
              _pairedDeviceTile(context),
              if (sharingViewModel != null) ...[
                const SizedBox(height: 24),
                _sharingControls(context),
              ],
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
    if (bluetooth.peerOnline) {
      return _DeviceTile(
        name: isWindows ? '已连接手机' : (device?.name ?? 'Windows 电脑'),
        status: '在线 · ${bluetooth.peerNetworkStatus ?? '网络状态检测中'}',
        icon: FluentIcons.devices2,
        severity: InfoBarSeverity.success,
        onManagePermissions: () => _managePermissions(context),
      );
    }
    if (bluetooth.hasPersistedPairing) {
      return _DeviceTile(
        name: bluetooth.pairedDeviceName ?? '已配对设备',
        status: '离线 · 应用配对已保存',
        icon: FluentIcons.devices2,
        severity: InfoBarSeverity.info,
        onManagePermissions: () => _managePermissions(context),
      );
    }
    if (device != null) {
      return _DeviceTile(
        name: device.name,
        status: '在线 · 尚未完成应用配对',
        icon: FluentIcons.devices2,
        severity: InfoBarSeverity.warning,
        onManagePermissions: () => _managePermissions(context),
      );
    }
    return _DeviceTile(
      name: isWindows && bluetooth.advertising ? 'NetworkSharing' : '尚未配对设备',
      status: isWindows && bluetooth.advertising ? '等待设备连接' : '暂无在线设备',
      icon: FluentIcons.bluetooth,
      severity: InfoBarSeverity.info,
      onManagePermissions: () => _managePermissions(context),
    );
  }

  Widget _sharingControls(BuildContext context) {
    final sharing = sharingViewModel!;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).resources.cardBackgroundFillColorDefault,
        border: Border.all(
          color: FluentTheme.of(context).resources.cardStrokeColorDefault,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('网络共享', style: FluentTheme.of(context).typography.subtitle),
          const SizedBox(height: 8),
          Text(sharing.status),
          if (sharing.ownsHotspot) ...[
            const SizedBox(height: 6),
            Text(
              '本应用开启的热点 · 在线客户端：${sharing.clientCount?.toString() ?? '系统暂未提供'}',
            ),
          ],
          if (sharing.pendingApproval) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton(
                  onPressed: sharing.busy ? null : () => sharing.approve(true),
                  child: const Text('允许开启'),
                ),
                const SizedBox(width: 8),
                Button(
                  onPressed: sharing.busy ? null : () => sharing.approve(false),
                  child: const Text('拒绝'),
                ),
              ],
            ),
          ],
          if (sharing.canRequest) ...[
            const SizedBox(height: 12),
            FilledButton(
              onPressed: sharing.requestNetwork,
              child: const Text('请求对方热点'),
            ),
          ],
          if (sharing.ownsHotspot || sharing.inSession) ...[
            const SizedBox(height: 8),
            Button(onPressed: () => sharing.stop(), child: const Text('停止共享')),
          ],
        ],
      ),
    );
  }

  Future<void> _managePermissions(BuildContext context) async {
    final sharing = sharingViewModel;
    if (sharing == null || !bluetoothViewModel.hasPersistedPairing) {
      await _openSystemPermissions();
      return;
    }
    var selected = sharing.permission;
    final result = await showDialog<SharingPermission>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => ContentDialog(
          title: Text('管理 ${bluetoothViewModel.pairedDeviceName ?? '已配对设备'}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('当此设备请求本机开启热点时：'),
              const SizedBox(height: 12),
              RadioGroup<SharingPermission>(
                groupValue: selected,
                onChanged: (value) {
                  if (value != null) setState(() => selected = value);
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final value in SharingPermission.values)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: RadioButton<SharingPermission>(
                          value: value,
                          content: Text(switch (value) {
                            SharingPermission.ask => '每次询问',
                            SharingPermission.allow => '自动同意',
                            SharingPermission.deny => '自动拒绝',
                          }),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              HyperlinkButton(
                onPressed: _openSystemPermissions,
                child: const Text('打开系统权限设置'),
              ),
            ],
          ),
          actions: [
            Button(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(selected),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (result != null) await sharing.setPermission(result);
  }

  Future<void> _openSystemPermissions() async {
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
