import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import 'dart:async';

import 'pairing_view_model.dart';
import '../bluetooth/bluetooth_view_model.dart';
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
  bool _automaticAdvertising = false;
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
        final bluetooth = widget.bluetoothViewModel;
        final isWindows = defaultTargetPlatform == TargetPlatform.windows;
        if (isWindows && !_automaticAdvertising && bluetooth != null) {
          _automaticAdvertising = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            unawaited(bluetooth.setAdvertising(true));
          });
        }
        if (isWindows && bluetooth != null) {
          bluetooth.setDisplayedPairingCode(
            vm.codeReady ? vm.pairingCode : null,
          );
        }
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
                    isWindows ? '将此验证码提供给连接的手机。' : '连接电脑后输入电脑屏幕显示的验证码。',
                    style: FluentTheme.of(context).typography.body,
                  ),
                  const SizedBox(height: 28),
                  InfoBar(
                    title: Text(isWindows ? '等待手机连接' : '连接 Windows 电脑'),
                    content: Text(
                      isWindows
                          ? '电脑持续广播 NetworkSharing 服务。保持蓝牙开启，手机连接后在本页显示配对码。'
                          : '扫描附近正在广播的 Windows 电脑，连接后输入电脑屏幕显示的应用配对码。',
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (vm.message != null) ...[
                    const SizedBox(height: 16),
                    InfoBar(
                      title: Text(vm.message!),
                      severity: vm.status == PairingStatus.paired
                          ? InfoBarSeverity.success
                          : InfoBarSeverity.warning,
                    ),
                  ],
                  if (widget.bluetoothViewModel != null && !isWindows) ...[
                    const SizedBox(height: 24),
                    _BluetoothDevices(
                      viewModel: widget.bluetoothViewModel!,
                      pairingViewModel: vm,
                      codeController: _codeController,
                    ),
                  ],
                  if (isWindows && widget.bluetoothViewModel != null) ...[
                    const SizedBox(height: 18),
                    AnimatedBuilder(
                      animation: widget.bluetoothViewModel!,
                      builder: (context, _) {
                        final bluetooth = widget.bluetoothViewModel!;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            InfoBar(
                              title: Text(
                                bluetooth.applicationPaired
                                    ? '应用配对成功'
                                    : bluetooth.hasPersistedPairing
                                    ? '已保存设备：${bluetooth.pairedDeviceName ?? '已配对手机'}'
                                    : bluetooth.advertising
                                    ? '正在广播，可供手机发现'
                                    : '电脑广播未开启',
                              ),
                              content: bluetooth.applicationPaired
                                  ? const Text('手机已验证电脑显示的配对码。')
                                  : bluetooth.hasPersistedPairing
                                  ? const Text(
                                      '上次应用配对已保存；当前设备连接状态以实时 BLE 链路为准。',
                                    )
                                  : null,
                              severity: bluetooth.applicationPaired
                                  ? InfoBarSeverity.success
                                  : bluetooth.advertising
                                  ? InfoBarSeverity.success
                                  : InfoBarSeverity.warning,
                            ),
                            if (vm.codeReady) ...[
                              const SizedBox(height: 16),
                              _ShowCode(viewModel: vm),
                            ] else
                              FilledButton(
                                onPressed: vm.status == PairingStatus.pairing
                                    ? null
                                    : vm.regenerateCode,
                                child: const Text('生成配对码'),
                              ),
                            if (bluetooth.connectedDeviceId != null) ...[
                              const SizedBox(height: 16),
                              if (vm.message != null)
                                InfoBar(
                                  title: Text(vm.message!),
                                  severity: vm.status == PairingStatus.paired
                                      ? InfoBarSeverity.success
                                      : InfoBarSeverity.warning,
                                ),
                              FilledButton(
                                onPressed: bluetooth.diagnosticSending
                                    ? null
                                    : bluetooth.sendDiagnosticMessage,
                                child: const Text('发送链路测试消息'),
                              ),
                              Button(
                                onPressed: () async {
                                  await bluetooth.disconnect();
                                  vm.setSystemPaired(false);
                                },
                                child: const Text('断开'),
                              ),
                            ],
                            if (bluetooth.transportError != null)
                              InfoBar(
                                title: Text(bluetooth.transportError!),
                                severity: InfoBarSeverity.error,
                              ),
                            if (bluetooth.diagnosticReceivedAt != null)
                              InfoBar(
                                title: const Text('已收到链路测试消息'),
                                content: Text(
                                  '接收时间：${bluetooth.diagnosticReceivedAt}',
                                ),
                                severity: InfoBarSeverity.info,
                              ),
                          ],
                        );
                      },
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
  const _BluetoothDevices({
    required this.viewModel,
    required this.pairingViewModel,
    required this.codeController,
  });
  final BluetoothViewModel viewModel;
  final PairingViewModel pairingViewModel;
  final TextEditingController codeController;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([viewModel, pairingViewModel]),
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '附近的 Windows 电脑',
          style: FluentTheme.of(context).typography.subtitle,
        ),
        const SizedBox(height: 12),
        if (viewModel.error != null)
          InfoBar(
            title: Text(viewModel.error!),
            severity: InfoBarSeverity.error,
          ),
        if (viewModel.transportError != null)
          InfoBar(
            title: Text(viewModel.transportError!),
            severity: InfoBarSeverity.error,
          ),
        FilledButton(
          onPressed: viewModel.scanning ? null : viewModel.scan,
          child: Text(viewModel.scanning ? '正在扫描…' : '扫描 Windows 电脑'),
        ),
        if (viewModel.scanning) const ProgressBar(),
        ...viewModel.discoveredDevices.map(
          (device) => Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: FluentTheme.of(context)
                  .resources
                  .cardBackgroundFillColorDefault,
              border: Border.all(
                color: FluentTheme.of(context).resources.cardStrokeColorDefault,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                const Icon(FluentIcons.bluetooth),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.name,
                        style: FluentTheme.of(context).typography.bodyStrong,
                      ),
                      const Text('NetworkSharing Windows 电脑'),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed:
                      viewModel.connecting ||
                          viewModel.connectedDeviceId != null
                      ? null
                      : () async {
                          await viewModel.connect(device);
                          if (viewModel.connectedDeviceId == device.id) {
                            pairingViewModel.setSystemPaired(true);
                            pairingViewModel.setMessage('已连接电脑，请输入电脑屏幕显示的配对码。');
                          }
                        },
                  child: Text(viewModel.connecting ? '正在连接…' : '连接'),
                ),
              ],
            ),
          ),
        ),
        if (viewModel.connectedDeviceId != null &&
            viewModel.applicationPaired) ...[
          const SizedBox(height: 12),
          const InfoBar(
            title: Text('应用配对成功'),
            content: Text('已恢复可信设备连接。'),
            severity: InfoBarSeverity.success,
          ),
        ] else if (viewModel.connectedDeviceId != null &&
            viewModel.pairingRestoring) ...[
          const SizedBox(height: 12),
          const InfoBar(
            title: Text('正在恢复应用配对…'),
            content: Text('正在验证此设备此前保存的配对凭据。'),
          ),
          const ProgressBar(),
        ] else if (viewModel.connectedDeviceId != null) ...[
          const SizedBox(height: 16),
          _EnterCode(
            controller: codeController,
            viewModel: pairingViewModel,
            onSubmit: () async {
              pairingViewModel.setEnteredCode(codeController.text);
              if (pairingViewModel.enteredCode.length != 6) {
                pairingViewModel.setMessage(
                  '请输入完整的 6 位配对码。',
                  nextStatus: PairingStatus.error,
                );
                return;
              }
              pairingViewModel.setMessage(
                '正在验证配对码。',
                nextStatus: PairingStatus.pairing,
              );
              final accepted = await viewModel.authenticatePairingCode(
                pairingViewModel.enteredCode,
              );
              pairingViewModel.setMessage(
                accepted ? '应用配对成功。' : '配对码校验失败或电脑未响应。',
                nextStatus: accepted
                    ? PairingStatus.paired
                    : PairingStatus.error,
              );
            },
          ),
          Row(
            children: [
              FilledButton(
                onPressed: viewModel.diagnosticSending
                    ? null
                    : viewModel.sendDiagnosticMessage,
                child: const Text('发送链路测试消息'),
              ),
              const SizedBox(width: 8),
              Button(
                onPressed: () async {
                  await viewModel.disconnect();
                  pairingViewModel.setSystemPaired(false);
                },
                child: const Text('断开'),
              ),
            ],
          ),
        ],
      ],
    ),
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
        Text('请在手机输入此配对码', style: FluentTheme.of(context).typography.subtitle),
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
  const _EnterCode({
    required this.controller,
    required this.viewModel,
    this.onSubmit,
  });
  final TextEditingController controller;
  final PairingViewModel viewModel;
  final Future<void> Function()? onSubmit;
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
            : () async {
                AppLogger.instance.info('ui', 'pairing.submit_clicked', {
                  'codeLength': viewModel.enteredCode.length,
                });
                if (onSubmit != null) {
                  await onSubmit!();
                } else {
                  await viewModel.submitCode();
                }
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
