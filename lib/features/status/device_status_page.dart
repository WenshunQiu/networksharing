import 'package:fluent_ui/fluent_ui.dart';

import '../../domain/connectivity.dart';
import 'connectivity_view_model.dart';

class DeviceStatusPage extends StatelessWidget {
  const DeviceStatusPage({required this.viewModel, super.key});
  final ConnectivityViewModel viewModel;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: viewModel,
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
              const SizedBox(height: 18),
              const InfoBar(
                title: Text('尚未配对设备'),
                content: Text('配对后可在这里查看设备和共享会话状态。'),
                severity: InfoBarSeverity.info,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
