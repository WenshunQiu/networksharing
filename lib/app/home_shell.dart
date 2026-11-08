import 'package:fluent_ui/fluent_ui.dart';

import '../features/pairing/pairing_page.dart';
import '../features/pairing/pairing_view_model.dart';
import '../features/status/device_status_page.dart';
import '../features/status/connectivity_view_model.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    required this.viewModel,
    required this.connectivity,
    super.key,
  });

  final PairingViewModel viewModel;
  final ConnectivityViewModel connectivity;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      PairingPage(viewModel: widget.viewModel),
      DeviceStatusPage(viewModel: widget.connectivity),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        if (wide) {
          return NavigationView(
            titleBar: const TitleBar(title: Text('NetworkSharing')),
            pane: NavigationPane(
              selected: _index,
              onChanged: (index) => setState(() => _index = index),
              displayMode: PaneDisplayMode.expanded,
              items: [
                PaneItem(
                  icon: const Icon(FluentIcons.link),
                  title: const Text('配对设备'),
                  body: pages[0],
                ),
                PaneItem(
                  icon: const Icon(FluentIcons.devices2),
                  title: const Text('设备状态'),
                  body: pages[1],
                ),
              ],
            ),
          );
        }
        return ScaffoldPage(
          header: PageHeader(
            title: const Text('NetworkSharing'),
            commandBar: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(FluentIcons.link),
                  onPressed: () => setState(() => _index = 0),
                ),
                IconButton(
                  icon: const Icon(FluentIcons.devices2),
                  onPressed: () => setState(() => _index = 1),
                ),
              ],
            ),
          ),
          content: pages[_index],
        );
      },
    );
  }
}
