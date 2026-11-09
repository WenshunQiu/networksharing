import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:networksharing/domain/connectivity.dart';
import 'package:networksharing/data/debug_notifications.dart';
import 'package:networksharing/data/platform_bluetooth_repository.dart';
import 'package:networksharing/features/bluetooth/bluetooth_repository.dart';
import 'package:networksharing/features/bluetooth/bluetooth_view_model.dart';
import 'package:networksharing/features/bluetooth/ble_protocol.dart';

class PendingBluetoothRepository implements BluetoothRepository {
  @override
  Stream<List<BluetoothDevice>> get discoveryResults => const Stream.empty();
  final pending = Completer<BluetoothSnapshot>();
  int calls = 0;
  @override
  Future<BluetoothSnapshot> inspect() {
    calls++;
    return pending.future;
  }

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

class FakeBluetoothRepository implements BluetoothRepository {
  final controller = StreamController<String>.broadcast();
  final discoveryController =
      StreamController<List<BluetoothDevice>>.broadcast();
  List<BluetoothDevice> scanResults = const [];
  String? connectedId;
  int connections = 0;
  int disconnections = 0;
  Future<void> Function(String)? onSend;
  bool isAdvertising = false;
  String? sentMessage;
  final sentMessages = <String>[];
  Completer<List<BluetoothDevice>>? pendingScan;

  @override
  Future<BluetoothSnapshot> inspect() async =>
      const BluetoothSnapshot(state: BluetoothState.ready);
  @override
  Future<List<BluetoothDevice>> scan({
    Duration duration = const Duration(seconds: 8),
  }) async => pendingScan?.future ?? scanResults;
  @override
  Future<void> startAdvertising() async => isAdvertising = true;
  @override
  Future<void> stopAdvertising() async => isAdvertising = false;
  @override
  Future<void> connect(String deviceId) async {
    connectedId = deviceId;
    connections++;
  }

  @override
  Future<void> pairSystemDevice(String deviceId) async {}
  @override
  Future<void> disconnect() async {
    connectedId = null;
    disconnections++;
  }

  @override
  Future<void> sendMessage(String message) async {
    sentMessage = message;
    sentMessages.add(message);
    await onSend?.call(message);
  }

  @override
  Stream<String> get messages => controller.stream;
  @override
  Stream<List<BluetoothDevice>> get discoveryResults =>
      discoveryController.stream;
}

class FakeConnectivityRepository implements ConnectivityRepository {
  int checks = 0;
  @override
  Future<ConnectivitySnapshot> check() async {
    checks++;
    return ConnectivitySnapshot(
      state: ConnectivityState.online,
      checkedAt: DateTime.now(),
      reachableHosts: const {'www.baidu.com'},
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('networksharing/bluetooth');
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => true);
  });

  test('only Android registers CCCD explicitly; WinRT supplies its own', () {
    expect(
      createControlService(includeCccd: true).characteristics.last.descriptors,
      hasLength(1),
    );
    expect(
      createControlService(includeCccd: false).characteristics.last.descriptors,
      isEmpty,
    );
  });

  test('control frames reassemble fragments in any order', () {
    final decoder = ControlFrameDecoder();
    const message = '{"type":"hello","value":"hello world"}';
    final frames = encodeControlFrames(message, 12);
    expect(frames.length, greaterThan(1));
    expect(decoder.add(frames.last), isNull);
    String? result;
    for (final frame in frames.take(frames.length - 1)) {
      result = decoder.add(frame) ?? result;
    }
    expect(result, message);
  });

  test('control frames reject empty and oversized messages', () {
    expect(() => encodeControlFrames('', 20), throwsFormatException);
    expect(
      () => encodeControlFrames('x' * (maxControlMessageBytes + 1), 20),
      throwsFormatException,
    );
    expect(() => encodeControlFrames('abc', 6), throwsFormatException);
    expect(() => ControlFrameDecoder().add([0, 0]), throwsFormatException);
  });

  test(
    'Bluetooth view model drives advertising, connection and messages',
    () async {
      final repository = FakeBluetoothRepository()
        ..scanResults = const [BluetoothDevice(id: 'peer', name: 'Phone')];
      final vm = BluetoothViewModel(repository);
      await vm.setAdvertising(true);
      expect(vm.advertising, isTrue);
      await vm.scan();
      expect(vm.discoveredDevices.single.id, 'peer');
      await vm.connect(vm.discoveredDevices.single);
      expect(vm.connectedDeviceId, 'peer');
      expect(
        vm.systemPairedDeviceIds,
        isEmpty,
        reason: 'A GATT connection must not imply a system Bluetooth bond',
      );
      await vm.sendDiagnosticMessage();
      expect(repository.sentMessage, startsWith('transport-check:'));
      repository.controller.add('reply');
      await Future<void>.delayed(Duration.zero);
      expect(vm.lastMessage, 'reply');
      await vm.disconnect();
      expect(vm.connectedDeviceId, isNull);
      vm.dispose();
      await repository.controller.close();
      await repository.discoveryController.close();
    },
  );

  test(
    'pairing code authentication succeeds and rejects an incorrect code',
    () async {
      final repository = FakeBluetoothRepository();
      final vm = BluetoothViewModel(repository);
      vm.connectedDeviceId = 'computer';
      vm.setDisplayedPairingCode('ABC234');

      final correct = vm.authenticatePairingCode('ABC234');
      await Future<void>.delayed(Duration.zero);
      repository.controller.add(
        '{"type":"pairing_auth_result","success":true,"resumeToken":"shared-token"}',
      );
      expect(await correct, isTrue);
      expect(vm.applicationPaired, isTrue);
      expect(repository.sentMessages, hasLength(1));

      vm.applicationPaired = false;
      final incorrect = vm.authenticatePairingCode('WRONG2');
      await Future<void>.delayed(Duration.zero);
      repository.controller.add(
        '{"type":"pairing_auth_result","success":false}',
      );
      expect(await incorrect, isFalse);
      expect(vm.applicationPaired, isFalse);
      expect(repository.sentMessages, hasLength(2));

      vm.dispose();
      await repository.controller.close();
      await repository.discoveryController.close();
    },
  );

  test('Windows accepts only its current displayed pairing code', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final repository = FakeBluetoothRepository();
    final connectivity = FakeConnectivityRepository();
    final vm = BluetoothViewModel(
      repository,
      connectivityRepository: connectivity,
    );
    vm.setDisplayedPairingCode('ABC234');
    vm.connecting = false;
    await vm.setAdvertising(true);

    repository.controller.add(
      '{"type":"pairing_auth_request","code":"WRONG2"}',
    );
    await Future<void>.delayed(Duration.zero);
    expect(vm.applicationPaired, isFalse);
    expect(
      repository.sentMessage,
      '{"type":"pairing_auth_result","success":false}',
    );

    repository.controller.add(
      '{"type":"pairing_auth_request","code":"ABC234"}',
    );
    await Future<void>.delayed(Duration.zero);
    expect(vm.applicationPaired, isTrue);
    expect(vm.hasPersistedPairing, isTrue);
    expect(vm.pairedDeviceName, '已配对手机');
    final authResult =
        jsonDecode(repository.sentMessage!) as Map<String, dynamic>;
    expect(authResult['type'], 'pairing_auth_result');
    expect(authResult['success'], isTrue);
    expect(authResult['resumeToken'], isA<String>());

    final persisted = SharedPreferencesAsync();
    expect(
      await persisted.getString('networksharing.pairedDeviceId.windows'),
      'windows-central',
    );
    expect(
      await persisted.getString('networksharing.pairResumeToken.windows'),
      authResult['resumeToken'],
    );

    await vm.sendDebugWifiCredentials('Debug AP', 'password123');
    expect(
      jsonDecode(repository.sentMessage!)['type'],
      'debug_wifi_credentials',
    );

    await vm.runNetworkProbe();
    expect(connectivity.checks, 1);
    expect(
      repository.sentMessages.any(
        (message) => message.contains('network_probe_result'),
      ),
      isTrue,
    );
    repository.controller.add(
      jsonEncode({
        'type': 'pairing_resume_request',
        'token': authResult['resumeToken'],
      }),
    );
    await Future<void>.delayed(Duration.zero);
    expect(jsonDecode(repository.sentMessage!)['success'], isTrue);

    vm.setDisplayedPairingCode(null);
    expect(
      vm.applicationPaired,
      isTrue,
      reason: 'code expiry must not invalidate an established session',
    );
    repository.controller.add(
      '{"type":"pairing_auth_request","code":"ABC234"}',
    );
    await Future<void>.delayed(Duration.zero);
    expect(vm.applicationPaired, isTrue);
    expect(
      repository.sentMessage,
      '{"type":"pairing_auth_result","success":false}',
    );
    vm.dispose();
    await repository.controller.close();
    await repository.discoveryController.close();
  });

  test(
    'saved Android pairing reconnects and resumes after heartbeat loss',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final prefs = SharedPreferencesAsync();
      await prefs.setString('networksharing.pairedDeviceId', 'computer');
      await prefs.setString('networksharing.pairedDeviceName', 'My PC');
      await prefs.setString('networksharing.pairResumeToken', 'saved-token');
      final repository = FakeBluetoothRepository()
        ..scanResults = const [BluetoothDevice(id: 'computer', name: 'My PC')];
      repository.onSend = (message) async {
        final data = jsonDecode(message);
        if (data['type'] == 'pairing_resume_request') {
          expect(data['token'], 'saved-token');
          repository.controller.add(
            '{"type":"pairing_resume_result","success":true}',
          );
        }
      };
      final vm = BluetoothViewModel(
        repository,
        connectivityRepository: FakeConnectivityRepository(),
        initialReconnectDelay: const Duration(milliseconds: 5),
        reconnectDelay: const Duration(milliseconds: 5),
        heartbeatInterval: const Duration(milliseconds: 15),
        peerTimeout: const Duration(milliseconds: 40),
        initialNetworkDelay: const Duration(days: 1),
      );
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(vm.applicationPaired, isTrue);
      expect(repository.connections, 1);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(repository.connections, greaterThanOrEqualTo(2));
      expect(vm.applicationPaired, isTrue);
      expect(vm.hasPersistedPairing, isTrue);
      await vm.disconnect();
      final connections = repository.connections;
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(
        repository.connections,
        connections,
        reason: 'manual disconnect suppresses reconnect',
      );
      vm.dispose();
      await repository.controller.close();
    },
  );

  test('rejected resume retains saved pairing for reauthentication', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final prefs = SharedPreferencesAsync();
    await prefs.setString('networksharing.pairedDeviceId', 'computer');
    await prefs.setString('networksharing.pairResumeToken', 'saved-token');
    final repository = FakeBluetoothRepository()
      ..scanResults = const [BluetoothDevice(id: 'computer', name: 'My PC')];
    repository.onSend = (message) async {
      if (jsonDecode(message)['type'] == 'pairing_resume_request') {
        repository.controller.add(
          '{"type":"pairing_resume_result","success":false}',
        );
      }
    };
    final vm = BluetoothViewModel(
      repository,
      initialReconnectDelay: const Duration(milliseconds: 5),
    );
    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(vm.applicationPaired, isFalse);
    expect(vm.hasPersistedPairing, isTrue);
    expect(
      await prefs.getString('networksharing.pairResumeToken'),
      'saved-token',
    );
    vm.dispose();
    await repository.controller.close();
  });

  test(
    'notification confirmation starts hotspot and shares credentials only once',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      const debugChannel = MethodChannel('networksharing/debug');
      var starts = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(debugChannel, (call) async {
            expect(call.method, 'startHotspot');
            starts++;
            return {
              'success': true,
              'enabled': true,
              'ssid': 'Test AP',
              'password': 'test12345',
            };
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(debugChannel, null);
      });
      final repository = FakeBluetoothRepository();
      final vm = BluetoothViewModel(repository);
      await vm.connect(const BluetoothDevice(id: 'computer', name: 'PC'));
      vm.applicationPaired = true;
      repository.onSend = (message) async {
        final data = jsonDecode(message);
        if (data['type'] == 'debug_wifi_credentials') {
          repository.controller.add(
            jsonEncode({
              'type': 'debug_wifi_credentials_ack',
              'transferId': data['transferId'],
            }),
          );
        }
      };
      repository.controller.add(
        '{"type":"hotspot_request","requestId":"request-one"}',
      );
      await Future<void>.delayed(Duration.zero);
      expect(vm.peerHotspotRequestPending, isTrue);
      await DebugNotifications.instance.onHotspotResponse!('request-one', true);
      await DebugNotifications.instance.onHotspotResponse!('request-one', true);
      expect(starts, 1);
      expect(vm.peerHotspotRequestPending, isFalse);
      expect(vm.wifiTransferStatus, '对端已确认收到 Wi-Fi 信息。');
      expect(
        repository.sentMessages.any(
          (message) =>
              jsonDecode(message)['type'] == 'hotspot_operation_result',
        ),
        isTrue,
      );
      vm.dispose();
      await repository.controller.close();
    },
  );

  test(
    'Windows resumes from persisted token after recreating view model',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final prefs = SharedPreferencesAsync();
      await prefs.setString(
        'networksharing.pairedDeviceId.windows',
        'windows-central',
      );
      await prefs.setString(
        'networksharing.pairedDeviceName.windows',
        'My phone',
      );
      await prefs.setString(
        'networksharing.pairResumeToken.windows',
        'saved-windows-token',
      );
      final repository = FakeBluetoothRepository();
      final vm = BluetoothViewModel(repository);
      await vm.setAdvertising(true);
      expect(vm.hasPersistedPairing, isTrue);
      expect(vm.applicationPaired, isFalse);
      repository.controller.add(
        '{"type":"pairing_resume_request","token":"saved-windows-token"}',
      );
      await Future<void>.delayed(Duration.zero);
      expect(vm.applicationPaired, isTrue);
      expect(jsonDecode(repository.sentMessage!)['success'], isTrue);
      vm.dispose();
      await repository.controller.close();
    },
  );

  test('scan shows discoveries before the scan duration completes', () async {
    final repository = FakeBluetoothRepository()..pendingScan = Completer();
    final vm = BluetoothViewModel(repository);
    final scan = vm.scan();
    expect(vm.scanning, isTrue);
    await Future<void>.delayed(Duration.zero);
    repository.discoveryController.add(const [
      BluetoothDevice(id: 'peer', name: 'Computer'),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(vm.discoveredDevices.single.name, 'Computer');
    repository.pendingScan!.complete(vm.discoveredDevices);
    await scan;
    expect(vm.scanning, isFalse);
    vm.dispose();
    await repository.controller.close();
    await repository.discoveryController.close();
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'Android adapter maps system devices and radio/permission states',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final repository = PlatformBluetoothRepository();
      for (final state in [
        'ready',
        'poweredOff',
        'permissionDenied',
        'unavailable',
      ]) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              expect(call.method, 'inspect');
              return {
                'state': state,
                'devices': [
                  {'id': 'peer-id', 'name': 'Computer'},
                ],
              };
            });
        final snapshot = await repository.inspect();
        expect(snapshot.state.name, state);
        expect(snapshot.devices.single.name, 'Computer');
      }
    },
  );

  test('unknown platform state is a failure, not ready', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => {'state': 'future', 'devices': []},
        );
    expect(
      (await PlatformBluetoothRepository().inspect()).state,
      BluetoothState.failed,
    );
  });

  test(
    'duplicate queries are ignored and late completion after dispose is safe',
    () async {
      final repository = PendingBluetoothRepository();
      final vm = BluetoothViewModel(repository);
      final query = vm.inspect();
      await vm.inspect();
      expect(repository.calls, 1);
      expect(vm.checking, isTrue);
      vm.dispose();
      repository.pending.complete(
        const BluetoothSnapshot(state: BluetoothState.ready),
      );
      await query;
      expect(vm.snapshot, isNull);
    },
  );

  test(
    'query failure clears progress and reports an actionable error',
    () async {
      final repository = PendingBluetoothRepository();
      final vm = BluetoothViewModel(repository);
      final query = vm.inspect();
      repository.pending.completeError(StateError('Bluetooth API unavailable'));
      await query;
      expect(vm.checking, isFalse);
      expect(vm.error, isNotNull);
      expect(vm.snapshot, isNull);
      vm.dispose();
    },
  );
}
