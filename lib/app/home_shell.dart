import 'package:fluent_ui/fluent_ui.dart';

import '../features/pairing/pairing_page.dart';
import '../features/pairing/pairing_view_model.dart';
import '../features/status/device_status_page.dart';
import '../features/status/connectivity_view_model.dart';
import '../features/settings/settings_page.dart';
import '../features/settings/settings_view_model.dart';
import '../features/bluetooth/bluetooth_view_model.dart';
import '../features/sharing/sharing_view_model.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    required this.viewModel,
    required this.connectivity,
    required this.settings,
    required this.bluetooth,
    required this.sharing,
    super.key,
  });

  final PairingViewModel viewModel;
  final ConnectivityViewModel connectivity;
  final SettingsViewModel settings;
  final BluetoothViewModel bluetooth;
  final SharingViewModel sharing;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      PairingPage(
        viewModel: widget.viewModel,
        bluetoothViewModel: widget.bluetooth,
      ),
      DeviceStatusPage(
        viewModel: widget.connectivity,
        bluetoothViewModel: widget.bluetooth,
        sharingViewModel: widget.sharing,
      ),
      SettingsPage(
        viewModel: widget.settings,
        bluetoothViewModel: widget.bluetooth,
      ),
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
                PaneItem(
                  icon: const Icon(FluentIcons.settings),
                  title: const Text('设置'),
                  body: pages[2],
                ),
              ],
            ),
          );
        }
        return ScaffoldPage(
          header: PageHeader(title: const Text('NetworkSharing')),
          content: pages[_index],
          padding: EdgeInsets.zero,
          footer: SafeArea(
            top: false,
            child: Container(
              height: 64,
              decoration: BoxDecoration(
                color: FluentTheme.of(context).micaBackgroundColor,
                border: Border(
                  top: BorderSide(
                    color: FluentTheme.of(context)
                        .resources
                        .surfaceStrokeColorDefault,
                  ),
                ),
              ),
              child: Row(
                children: [
                  _BottomNavigationItem(
                    key: const ValueKey('bottom-nav-pairing'),
                    icon: FluentIcons.link,
                    label: '配对',
                    selected: _index == 0,
                    onPressed: () => setState(() => _index = 0),
                  ),
                  _BottomNavigationItem(
                    key: const ValueKey('bottom-nav-status'),
                    icon: FluentIcons.devices2,
                    label: '设备状态',
                    selected: _index == 1,
                    onPressed: () => setState(() => _index = 1),
                  ),
                  _BottomNavigationItem(
                    key: const ValueKey('bottom-nav-settings'),
                    icon: FluentIcons.settings,
                    label: '设置',
                    selected: _index == 2,
                    onPressed: () => setState(() => _index = 2),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BottomNavigationItem extends StatelessWidget {
  const _BottomNavigationItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: ToggleButton(
        checked: selected,
        onChanged: (_) => onPressed(),
        semanticLabel: label,
        child: Tooltip(message: label, child: Icon(icon, size: 20)),
      ),
    ),
  );
}
