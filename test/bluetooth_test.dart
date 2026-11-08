import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
  Future<void> connect(String deviceId) async => connectedId = deviceId;
  @override
  Future<void> pairSystemDevice(String deviceId) async {}
  @override
  Future<void> disconnect() async => connectedId = null;
  @override
  Future<void> sendMessage(String message) async {
    sentMessage = message;
    sentMessages.add(message);
  }

  @override
  Stream<String> get messages => controller.stream;
  @override
  Stream<List<BluetoothDevice>> get discoveryResults =>
      discoveryController.stream;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('networksharing/bluetooth');

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
        '{"type":"pairing_auth_result","success":true}',
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
    final repository = FakeBluetoothRepository();
    final vm = BluetoothViewModel(repository);
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
    expect(
      repository.sentMessage,
      '{"type":"pairing_auth_result","success":true}',
    );

    vm.setDisplayedPairingCode(null);
    expect(vm.applicationPaired, isFalse);
    repository.controller.add(
      '{"type":"pairing_auth_request","code":"ABC234"}',
    );
    await Future<void>.delayed(Duration.zero);
    expect(vm.applicationPaired, isFalse);
    expect(
      repository.sentMessage,
      '{"type":"pairing_auth_result","success":false}',
    );
    vm.dispose();
    await repository.controller.close();
    await repository.discoveryController.close();
  });

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
