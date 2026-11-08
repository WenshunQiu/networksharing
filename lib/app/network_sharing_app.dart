import 'package:fluent_ui/fluent_ui.dart';

import '../data/rust_pairing_repository.dart';
import '../features/pairing/pairing_view_model.dart';
import '../features/pairing/pairing_repository.dart';
import 'home_shell.dart';
import '../data/http_connectivity_repository.dart';
import '../features/status/connectivity_view_model.dart';

class NetworkSharingApp extends StatefulWidget {
  const NetworkSharingApp({this.pairingRepository, super.key});

  final PairingRepository? pairingRepository;

  @override
  State<NetworkSharingApp> createState() => _NetworkSharingAppState();
}

class _NetworkSharingAppState extends State<NetworkSharingApp> {
  late final PairingViewModel _viewModel;
  late final ConnectivityViewModel _connectivity;

  @override
  void initState() {
    super.initState();
    _viewModel = PairingViewModel(
      repository: widget.pairingRepository ?? RustPairingRepository(),
    );
    _connectivity = ConnectivityViewModel(HttpConnectivityRepository());
  }

  @override
  void dispose() {
    _viewModel.dispose();
    _connectivity.dispose();
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
      ),
      darkTheme: FluentThemeData(
        brightness: Brightness.dark,
        accentColor: Colors.blue,
      ),
      home: HomeShell(viewModel: _viewModel, connectivity: _connectivity),
    );
  }
}
