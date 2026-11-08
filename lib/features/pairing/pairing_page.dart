import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import 'pairing_view_model.dart';

class PairingPage extends StatefulWidget {
  const PairingPage({required this.viewModel, super.key});
  final PairingViewModel viewModel;
  @override
  State<PairingPage> createState() => _PairingPageState();
}

class _PairingPageState extends State<PairingPage> {
  final _codeController = TextEditingController();
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
                    onChanged: vm.setShowingCode,
                    content: Text(vm.isShowingCode ? '显示配对码' : '输入配对码'),
                  ),
                  const SizedBox(height: 20),
                  const InfoBar(
                    title: Text('配对界面预览'),
                    content: Text('目前仅支持本地生成与输入配对码，尚未广播或验证蓝牙配对码。'),
                    severity: InfoBarSeverity.info,
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
                  const SizedBox(height: 28),
                  const InfoBar(
                    title: Text('蓝牙尚未连接'),
                    content: Text('完成配对后，设备将在此显示连接和网络共享状态。'),
                    severity: InfoBarSeverity.info,
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
          onPressed: viewModel.regenerateCode,
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
            : viewModel.submitCode,
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
