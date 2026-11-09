import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';

import '../data/rust_pairing_repository.dart';
import '../features/pairing/pairing_view_model.dart';
import '../features/pairing/pairing_repository.dart';
import 'home_shell.dart';
import '../data/http_connectivity_repository.dart';
import '../features/status/connectivity_view_model.dart';
import '../data/shared_preferences_settings_repository.dart';
import '../features/settings/settings_view_model.dart';
import '../features/settings/settings_repository.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/platform_bluetooth_repository.dart';
import '../features/bluetooth/bluetooth_view_model.dart';
import '../features/bluetooth/bluetooth_repository.dart';
import '../features/sharing/sharing_view_model.dart';

String systemFontFamilyForPlatform(TargetPlatform platform) =>
    switch (platform) {
      TargetPlatform.windows => 'Microsoft YaHei UI',
      TargetPlatform.android => 'sans-serif',
      _ => 'sans-serif',
    };

class NetworkSharingApp extends StatefulWidget {
  const NetworkSharingApp({
    this.pairingRepository,
    this.settingsRepository,
    this.bluetoothRepository,
    super.key,
  });

  final SettingsRepository? settingsRepository;
  final BluetoothRepository? bluetoothRepository;

  final PairingRepository? pairingRepository;

  @override
  State<NetworkSharingApp> createState() => _NetworkSharingAppState();
}

class _NetworkSharingAppState extends State<NetworkSharingApp> {
  late final PairingViewModel _viewModel;
  late final ConnectivityViewModel _connectivity;
  late final SettingsViewModel _settings;
  late final BluetoothViewModel _bluetooth;
  late final SharingViewModel _sharing;

  String get _systemFontFamily =>
      systemFontFamilyForPlatform(defaultTargetPlatform);

  @override
  void initState() {
    super.initState();
    _viewModel = PairingViewModel(
      repository: widget.pairingRepository ?? RustPairingRepository(),
    );
    _connectivity = ConnectivityViewModel(HttpConnectivityRepository());
    _settings = SettingsViewModel(
      widget.settingsRepository ??
          SharedPreferencesSettingsRepository(SharedPreferencesAsync()),
    );
    _bluetooth = BluetoothViewModel(
      widget.bluetoothRepository ?? PlatformBluetoothRepository(),
      autoRecoverOnRestore: false,
    );
    _sharing = SharingViewModel(_bluetooth, _connectivity, _settings);
  }

  @override
  void dispose() {
    _sharing.dispose();
    _viewModel.dispose();
    _connectivity.dispose();
    _settings.dispose();
    _bluetooth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FluentApp(
      title: 'NetworkSharing',
      debugShowCheckedModeBanner: false,
      theme: FluentThemeData(
        brightness: Brightness.light,
        accentColor: Colors.blue,
        visualDensity: VisualDensity.standard,
        fontFamily: _systemFontFamily,
      ),
      darkTheme: FluentThemeData(
        brightness: Brightness.dark,
        accentColor: Colors.blue,
        fontFamily: _systemFontFamily,
      ),
      home: HomeShell(
        viewModel: _viewModel,
        connectivity: _connectivity,
        settings: _settings,
        bluetooth: _bluetooth,
        sharing: _sharing,
      ),
    );
  }
}
