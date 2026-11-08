import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import 'pairing_view_model.dart';
import '../bluetooth/bluetooth_view_model.dart';
import '../bluetooth/bluetooth_repository.dart';
import '../../data/app_logger.dart';

class PairingPage extends StatefulWidget {
  const PairingPage({
    required this.viewModel,
    this.bluetoothViewModel,
    super.key,
  });
  final PairingViewModel viewModel;
  final BluetoothViewModel? bluetoothViewModel;
  @override
  State<PairingPage> createState() => _PairingPageState();
}

class _PairingPageState extends State<PairingPage> {
  final _codeController = TextEditingController();
  final _log = AppLogger.instance;
  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.viewModel,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final vm = widget.viewModel;
        return SingleChildScrollView(
          padding: EdgeInsets.all(constraints.maxWidth < 520 ? 20 : 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '连接你的设备',
                    style: FluentTheme.of(context).typography.title,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '在一端显示配对码，在另一端输入。',
                    style: FluentTheme.of(context).typography.body,
                  ),
                  const SizedBox(height: 28),
                  ToggleSwitch(
                    checked: vm.isShowingCode,
                    onChanged: (value) {
                      _log.info('ui', 'pairing.mode_changed', {
                        'mode': value ? 'show_code' : 'enter_code',
                      });
                      vm.setShowingCode(value);
                    },
                    content: Text(vm.isShowingCode ? '显示配对码' : '输入配对码'),
                  ),
                  const SizedBox(height: 20),
                  const InfoBar(
                    title: Text('应用配对认证尚未接入'),
                    content: Text('BLE 连接仅建立传输通道，不代表设备已认证；请勿通过此通道发送热点凭据。'),
                    severity: InfoBarSeverity.warning,
                  ),
                  const SizedBox(height: 16),
                  if (vm.isShowingCode)
                    _ShowCode(viewModel: vm)
                  else
                    _EnterCode(controller: _codeController, viewModel: vm),
                  if (vm.message != null) ...[
                    const SizedBox(height: 16),
                    InfoBar(
                      title: Text(vm.message!),
                      severity: vm.status == PairingStatus.paired
                          ? InfoBarSeverity.success
                          : InfoBarSeverity.warning,
                    ),
                  ],
                  if (widget.bluetoothViewModel != null) ...[
                    const SizedBox(height: 24),
                    _BluetoothDevices(
                      viewModel: widget.bluetoothViewModel!,
                      showingCode: vm.isShowingCode,
                    ),
                  ],
                  const SizedBox(height: 28),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _BluetoothDevices extends StatelessWidget {
  const _BluetoothDevices({required this.viewModel, required this.showingCode});
  final BluetoothViewModel viewModel;
  final bool showingCode;

  String _state(BluetoothState state) => switch (state) {
    BluetoothState.ready => '蓝牙已开启',
    BluetoothState.poweredOff => '蓝牙已关闭，请在系统设置中开启',
    BluetoothState.unavailable => '此设备没有可用的蓝牙适配器',
    BluetoothState.permissionDenied => '缺少附近设备权限，请在系统设置中允许',
    BluetoothState.failed => '读取蓝牙状态失败，请重试',
  };

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: viewModel,
    builder: (context, _) {
      final snapshot = viewModel.snapshot;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '已绑定的蓝牙设备',
                  style: FluentTheme.of(context).typography.subtitle,
                ),
              ),
              IconButton(
                icon: const Icon(FluentIcons.refresh),
                onPressed: viewModel.checking ? null : viewModel.inspect,
              ),
            ],
          ),
          if (viewModel.checking) const ProgressBar(),
          if (viewModel.error != null)
            InfoBar(
              title: Text(viewModel.error!),
              severity: InfoBarSeverity.error,
            ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: viewModel.scanning ? null : viewModel.scan,
            child: Text(
              viewModel.scanning
                  ? '正在扫描 NetworkSharing 设备…'
                  : '扫描 NetworkSharing 设备',
            ),
          ),
          if (showingCode) ...[
            const SizedBox(height: 8),
            ToggleSwitch(
              checked: viewModel.advertising,
              onChanged: viewModel.setAdvertising,
              content: Text(
                viewModel.advertising ? '正在广播，可被另一端发现' : '允许另一端发现此设备',
              ),
            ),
          ],
          if (viewModel.scanning) const ProgressBar(),
          if (viewModel.transportError != null)
            InfoBar(
              title: Text(viewModel.transportError!),
              severity: InfoBarSeverity.error,
            ),
          if (viewModel.connectedDeviceId != null) ...[
            const SizedBox(height: 12),
            InfoBar(
              title: const Text('BLE 传输已连接，应用身份尚未认证'),
              content: Text('设备 ID：${viewModel.connectedDeviceId}'),
              severity: InfoBarSeverity.warning,
            ),
            Row(
              children: [
                FilledButton(
                  onPressed: viewModel.sendDiagnosticMessage,
                  child: const Text('发送链路测试消息'),
                ),
                const SizedBox(width: 8),
                Button(
                  onPressed: viewModel.disconnect,
                  child: const Text('断开'),
                ),
              ],
            ),
          ],
          if (viewModel.lastMessage != null)
            InfoBar(
              title: const Text('收到 BLE 消息'),
              content: Text(viewModel.lastMessage!),
              severity: InfoBarSeverity.info,
            ),
          if (viewModel.discoveredDevices.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...viewModel.discoveredDevices.map(
              (device) => ListTile(
                leading: const Icon(FluentIcons.bluetooth),
                title: Text(device.name),
                subtitle: const Text('NetworkSharing BLE；尚未认证'),
                trailing: Button(
                  onPressed:
                      viewModel.connecting ||
                          viewModel.connectedDeviceId != null
                      ? null
                      : () => viewModel.connect(device),
                  child: Text(viewModel.connecting ? '正在连接…' : '连接传输'),
                ),
              ),
            ),
          ] else if (!viewModel.scanning &&
              snapshot?.state == BluetoothState.ready)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('扫描附近设备后，结果将在此显示。'),
            ),
          if (snapshot != null) ...[
            const SizedBox(height: 8),
            Text(_state(snapshot.state)),
            if (snapshot.state == BluetoothState.ready &&
                snapshot.devices.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('未发现系统已绑定设备。'),
              )
            else
              ...snapshot.devices.map(
                (device) => ListTile(
                  leading: const Icon(FluentIcons.bluetooth),
                  title: Text(device.name),
                  subtitle: const Text('系统已绑定；尚未完成应用配对认证'),
                ),
              ),
          ] else if (!viewModel.checking)
            const Text('检查蓝牙状态并列出系统已绑定设备。'),
        ],
      );
    },
  );
}

class _ShowCode extends StatelessWidget {
  const _ShowCode({required this.viewModel});
  final PairingViewModel viewModel;
  @override
  Widget build(BuildContext context) {
    final remaining = viewModel.remaining;
    final time =
        '${remaining.inMinutes}:${(remaining.inSeconds % 60).toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '请在另一台设备输入此配对码',
          style: FluentTheme.of(context).typography.subtitle,
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 18),
          decoration: BoxDecoration(
            color: FluentTheme.of(context).resources.subtleFillColorSecondary,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child: SelectableText(
              viewModel.pairingCode.split('').join(' '),
              style: FluentTheme.of(context).typography.titleLarge,
              textAlign: TextAlign.center,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text('有效时间 $time', textAlign: TextAlign.center),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: () {
            AppLogger.instance.info('ui', 'pairing.code_regenerate_clicked');
            viewModel.regenerateCode();
          },
          child: const Text('重新生成配对码'),
        ),
      ],
    );
  }
}

class _EnterCode extends StatelessWidget {
  const _EnterCode({required this.controller, required this.viewModel});
  final TextEditingController controller;
  final PairingViewModel viewModel;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('输入另一台设备显示的配对码', style: FluentTheme.of(context).typography.subtitle),
      const SizedBox(height: 16),
      TextBox(
        controller: controller,
        maxLength: 6,
        enabled: viewModel.status != PairingStatus.pairing,
        placeholder: '6 位配对码',
        textCapitalization: TextCapitalization.characters,
        onChanged: viewModel.setEnteredCode,
      ),
      const SizedBox(height: 14),
      FilledButton(
        onPressed: viewModel.status == PairingStatus.pairing
            ? null
            : () {
                AppLogger.instance.info('ui', 'pairing.submit_clicked', {
                  'codeLength': viewModel.enteredCode.length,
                });
                viewModel.submitCode();
              },
        child: viewModel.status == PairingStatus.pairing
            ? const SizedBox.square(
                dimension: 18,
                child: ProgressRing(strokeWidth: 2),
              )
            : const Text('开始配对'),
      ),
    ],
  );
}
