import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:networksharing/app/network_sharing_app.dart';
import 'package:networksharing/features/pairing/pairing_repository.dart';
import 'package:networksharing/features/settings/settings_repository.dart';
import 'package:networksharing/domain/app_settings.dart';
import 'package:networksharing/features/bluetooth/bluetooth_repository.dart';
import 'package:networksharing/features/bluetooth/bluetooth_view_model.dart';
import 'package:networksharing/features/status/connectivity_view_model.dart';
import 'package:networksharing/features/status/device_status_page.dart';
import 'package:networksharing/domain/connectivity.dart';

void main() {
  for (final width in [390.0, 1200.0]) {
    testWidgets('pairing page adapts at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        NetworkSharingApp(
          pairingRepository: TestPairingRepository(),
          settingsRepository: TestSettingsRepository(),
          bluetoothRepository: TestBluetoothRepository(),
        ),
      );
      await tester.pump();
      expect(find.text('连接你的设备'), findsOneWidget);
      expect(find.text('扫描 Windows 电脑'), findsOneWidget);
      expect(find.text('重新生成配对码'), findsNothing);
      if (width < 760) {
        expect(
          find.byKey(const ValueKey('bottom-nav-pairing')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('bottom-nav-status')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('bottom-nav-settings')),
          findsOneWidget,
        );
        expect(find.byIcon(FluentIcons.link), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('narrow navigation switches pages from the bottom bar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      NetworkSharingApp(
        pairingRepository: TestPairingRepository(),
        settingsRepository: TestSettingsRepository(),
        bluetoothRepository: TestBluetoothRepository(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bottom-nav-settings')));
    await tester.pumpAndSettle();
    expect(find.text('偏好自动保存在本机'), findsOneWidget);
    expect(find.text('重新生成配对码'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('device status shows the paired peer state', (tester) async {
    final bluetooth = BluetoothViewModel(TestBluetoothRepository())
      ..connectedDeviceId = 'computer'
      ..discoveredDevices = const [
        BluetoothDevice(id: 'computer', name: 'Office PC'),
      ]
      ..applicationPaired = true
      ..peerOnline = true;
    final connectivity = ConnectivityViewModel(_TestConnectivityRepository());
    await tester.pumpWidget(
      FluentApp(
        home: ScaffoldPage(
          content: DeviceStatusPage(
            viewModel: connectivity,
            bluetoothViewModel: bluetooth,
          ),
        ),
      ),
    );
    expect(find.text('Office PC'), findsOneWidget);
    expect(find.text('在线 · 网络状态检测中'), findsOneWidget);
    expect(tester.takeException(), isNull);
    bluetooth.dispose();
    connectivity.dispose();
    await tester.pumpWidget(const SizedBox());
  });
}

class _TestConnectivityRepository implements ConnectivityRepository {
  @override
  Future<ConnectivitySnapshot> check() async => ConnectivitySnapshot(
    state: ConnectivityState.offline,
    checkedAt: DateTime.now(),
    reachableHosts: const {},
  );
}

class TestSettingsRepository implements SettingsRepository {
  @override
  Future<AppSettings> load() async => const AppSettings();

  @override
  Future<void> save(AppSettings settings) async {}
}

class TestBluetoothRepository implements BluetoothRepository {
  @override
  Stream<List<BluetoothDevice>> get discoveryResults => const Stream.empty();

  @override
  Future<BluetoothSnapshot> inspect() async =>
      const BluetoothSnapshot(state: BluetoothState.unavailable);

  @override
  Future<List<BluetoothDevice>> scan({
    Duration duration = const Duration(seconds: 8),
  }) async => const [];

  @override
  Stream<String> get messages => const Stream.empty();

  @override
  Future<void> startAdvertising() async {}

  @override
  Future<void> stopAdvertising() async {}

  @override
  Future<void> connect(String deviceId) async {}
  @override
  Future<void> pairSystemDevice(String deviceId) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> sendMessage(String message) async {}
}

class TestPairingRepository implements PairingRepository {
  @override
  Future<PairingCodeSession> createSession() async => PairingCodeSession(
    sessionId: 'test-session',
    code: 'ABC234',
    expiresAt: DateTime.now().add(const Duration(minutes: 5)),
  );
  @override
  Future<PairingResult> pair(String code) async => const PairingResult(
    success: false,
    message: 'Bluetooth transport unavailable.',
  );
}
