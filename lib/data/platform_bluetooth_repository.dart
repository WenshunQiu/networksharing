import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'dart:async';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart' as ble;

import '../features/bluetooth/bluetooth_repository.dart';
import '../features/bluetooth/ble_protocol.dart';
import 'app_logger.dart';
import '../src/rust/api/bluetooth.dart' as rust_bluetooth;

class PlatformBluetoothRepository implements BluetoothRepository {
  late final controlService = createControlService(
    includeCccd: defaultTargetPlatform == TargetPlatform.android,
  );
  final _log = AppLogger.instance;
  static const _channel = MethodChannel('networksharing/bluetooth');
  ble.CentralManager? _centralInstance;
  ble.CentralManager get _central => _centralInstance ??= ble.CentralManager();
  ble.PeripheralManager? _peripheralInstance;
  ble.PeripheralManager get _peripheral =>
      _peripheralInstance ??= ble.PeripheralManager();
  final StreamController<String> _messages = StreamController.broadcast();
  final StreamController<List<BluetoothDevice>> _discoveryResults =
      StreamController.broadcast();
  StreamSubscription<ble.GATTCharacteristicWriteRequestedEventArgs>?
  _writeSubscription;
  StreamSubscription<ble.CentralConnectionStateChangedEventArgs>?
  _peripheralConnectionSubscription;
  StreamSubscription<ble.GATTCharacteristicNotifyStateChangedEventArgs>?
  _notifyStateSubscription;
  StreamSubscription<ble.GATTCharacteristicNotifiedEventArgs>?
  _notifySubscription;
  ble.Peripheral? _connectedPeripheral;
  final Map<String, ble.GATTCharacteristic> _remoteCharacteristics = {};
  final Map<String, ble.Peripheral> _discoveredPeripherals = {};
  final Map<String, ble.Central> _subscribedCentrals = {};
  final ControlFrameDecoder _peripheralDecoder = ControlFrameDecoder();
  final ControlFrameDecoder _centralDecoder = ControlFrameDecoder();

  @override
  Future<BluetoothSnapshot> inspect() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final data = await _channel.invokeMapMethod<String, dynamic>('inspect');
      if (data == null) {
        return const BluetoothSnapshot(state: BluetoothState.failed);
      }
      return BluetoothSnapshot(
        state: _parseState(data['state'] as String?),
        devices: (data['devices'] as List<dynamic>? ?? const [])
            .whereType<Map<dynamic, dynamic>>()
            .map(
              (device) => BluetoothDevice(
                id: device['id']?.toString() ?? '',
                name: device['name']?.toString() ?? 'Bluetooth device',
              ),
            )
            .toList(growable: false),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.windows) {
      final snapshot = await rust_bluetooth.inspectWindowsBluetooth();
      return BluetoothSnapshot(
        state: switch (snapshot.availability) {
          rust_bluetooth.BluetoothAvailability.ready => BluetoothState.ready,
          rust_bluetooth.BluetoothAvailability.poweredOff =>
            BluetoothState.poweredOff,
          rust_bluetooth.BluetoothAvailability.unavailable =>
            BluetoothState.unavailable,
          rust_bluetooth.BluetoothAvailability.permissionDenied =>
            BluetoothState.permissionDenied,
          rust_bluetooth.BluetoothAvailability.failed => BluetoothState.failed,
        },
        devices: snapshot.devices
            .map((peer) => BluetoothDevice(id: peer.id, name: peer.name))
            .toList(growable: false),
      );
    }
    return const BluetoothSnapshot(state: BluetoothState.unavailable);
  }

  @override
  Future<List<BluetoothDevice>> scan({
    Duration duration = const Duration(seconds: 8),
  }) async {
    _log.info('bluetooth', 'scan.requested', {
      'durationMs': duration.inMilliseconds,
    });
    await _prepareManager(_central, 'central');
    final discovered = <String, BluetoothDevice>{};
    _discoveredPeripherals.clear();
    final subscription = _central.discovered.listen((event) {
      final id = event.peripheral.uuid.toString();
      _discoveredPeripherals[id] = event.peripheral;
      discovered[id] = BluetoothDevice(
        id: id,
        name: event.advertisement.name?.trim().isNotEmpty == true
            ? event.advertisement.name!.trim()
            : '未命名蓝牙设备',
      );
      _log.info('bluetooth', 'scan.device_found', {
        'namePresent': event.advertisement.name?.trim().isNotEmpty == true,
        'rssi': event.rssi,
        'resultCount': discovered.length,
      });
      _discoveryResults.add(discovered.values.toList(growable: false));
    });
    try {
      await _central.startDiscovery(
        serviceUUIDs: [ble.UUID.fromString(controlServiceUuid)],
      );
      _log.info('bluetooth', 'scan.started');
      await Future<void>.delayed(duration);
      _log.info('bluetooth', 'scan.completed', {
        'resultCount': discovered.length,
      });
    } catch (error) {
      _log.error('bluetooth', 'scan.failed', {'error': _errorCode(error)});
      rethrow;
    } finally {
      try {
        await _central.stopDiscovery();
      } finally {
        await subscription.cancel();
      }
    }
    return discovered.values.toList(growable: false);
  }

  @override
  Stream<List<BluetoothDevice>> get discoveryResults =>
      _discoveryResults.stream;

  @override
  Stream<String> get messages => _messages.stream;

  @override
  Future<void> startAdvertising() async {
    _log.info('bluetooth', 'advertising.requested');
    try {
      await _prepareManager(_peripheral, 'peripheral');
      await _peripheral.addService(controlService);
      await _writeSubscription?.cancel();
      await _notifyStateSubscription?.cancel();
      if (defaultTargetPlatform != TargetPlatform.windows) {
        await _peripheralConnectionSubscription?.cancel();
        _peripheralConnectionSubscription = _peripheral.connectionStateChanged
            .listen((event) {
              if (event.state == ble.ConnectionState.disconnected) {
                _subscribedCentrals.remove(event.central.uuid.toString());
                _peripheralDecoder.reset();
                _log.info('bluetooth', 'gatt.remote_disconnected');
              }
            });
      }
      _notifyStateSubscription = _peripheral.characteristicNotifyStateChanged
          .listen((event) {
            if (event.characteristic.uuid.toString() != controlNotifyUuid) {
              return;
            }
            final id = event.central.uuid.toString();
            if (event.state) {
              _subscribedCentrals[id] = event.central;
            } else {
              _subscribedCentrals.remove(id);
            }
            _log.info(
              'bluetooth',
              event.state
                  ? 'gatt.notifications_enabled'
                  : 'gatt.notifications_disabled',
              {'subscriberCount': _subscribedCentrals.length},
            );
          });
      _writeSubscription = _peripheral.characteristicWriteRequested.listen((
        event,
      ) async {
        if (event.characteristic.uuid.toString() != controlWriteUuid) return;
        try {
          _log.debug('bluetooth', 'gatt.write_received', {
            'bytes': event.request.value.length,
            'offset': event.request.offset,
          });
          final message = _peripheralDecoder.add(event.request.value);
          if (message != null) _messages.add(message);
          await _peripheral.respondWriteRequest(event.request);
        } catch (error) {
          _log.error('bluetooth', 'gatt.write_rejected', {
            'error': _errorCode(error),
          });
          await _peripheral.respondWriteRequestWithError(
            event.request,
            error: ble.GATTError.invalidAttributeValueLength,
          );
        }
      });
      await _peripheral.startAdvertising(
        ble.Advertisement(
          serviceUUIDs: [ble.UUID.fromString(controlServiceUuid)],
        ),
      );
      _advertising = true;
      _log.info('bluetooth', 'advertising.started');
    } catch (error) {
      _log.error('bluetooth', 'advertising.failed', {
        'error': _errorCode(error),
      });
      rethrow;
    }
  }

  @override
  Future<void> stopAdvertising() async {
    _log.info('bluetooth', 'advertising.stop_requested');
    await _peripheral.stopAdvertising();
    _advertising = false;
    await _writeSubscription?.cancel();
    _writeSubscription = null;
    await _peripheralConnectionSubscription?.cancel();
    _peripheralConnectionSubscription = null;
    await _notifyStateSubscription?.cancel();
    _notifyStateSubscription = null;
    _subscribedCentrals.clear();
    await _peripheral.removeService(controlService);
    _log.info('bluetooth', 'advertising.stopped');
  }

  @override
  Future<void> connect(String deviceId) async {
    _log.info('bluetooth', 'connection.requested');
    try {
      await _prepareManager(_central, 'central');
      final peripheral = _discoveredPeripherals[deviceId];
      if (peripheral == null) {
        throw StateError('bluetooth_device_not_discovered');
      }
      await _central.connect(peripheral);
      _log.info('bluetooth', 'connection.link_established');
      _connectedPeripheral = peripheral;
      final services = await _central.discoverGATT(peripheral);
      _log.info('bluetooth', 'gatt.discovery_completed', {
        'serviceCount': services.length,
      });
      _remoteCharacteristics.clear();
      final characteristics = services
          .where((service) => service.uuid.toString() == controlServiceUuid)
          .expand((service) => service.characteristics);
      for (final characteristic in characteristics) {
        _remoteCharacteristics[characteristic.uuid.toString()] = characteristic;
      }
      final write = _remoteCharacteristics[controlWriteUuid];
      final notify = _remoteCharacteristics[controlNotifyUuid];
      if (write == null || notify == null) {
        throw StateError('networksharing_gatt_service_incomplete');
      }
      _log.info('bluetooth', 'gatt.characteristics_ready', {
        'hasWrite': true,
        'hasNotify': true,
        'notifyDescriptorCount': notify.descriptors.length,
      });
      await _notifySubscription?.cancel();
      _notifySubscription = _central.characteristicNotified.listen((event) {
        if (event.peripheral.uuid != peripheral.uuid ||
            event.characteristic.uuid.toString() != controlNotifyUuid) {
          return;
        }
        try {
          final message = _centralDecoder.add(event.value);
          if (message != null) {
            _log.info('bluetooth', 'gatt.message_received', {
              'bytes': message.length,
            });
            _messages.add(message);
          }
        } catch (error) {
          _log.error('bluetooth', 'gatt.notification_decode_failed', {
            'error': _errorCode(error),
          });
          _messages.addError(error);
        }
      });
      await _central.setCharacteristicNotifyState(
        peripheral,
        notify,
        state: true,
      );
      _log.info('bluetooth', 'gatt.notifications_subscribed');
    } catch (error) {
      _log.error('bluetooth', 'connection.failed', {
        'error': _errorCode(error),
      });
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    _log.info('bluetooth', 'connection.disconnect_requested');
    final peripheral = _connectedPeripheral;
    if (peripheral != null) await _central.disconnect(peripheral);
    _connectedPeripheral = null;
    _remoteCharacteristics.clear();
    _centralDecoder.reset();
    await _notifySubscription?.cancel();
    _notifySubscription = null;
    _log.info('bluetooth', 'connection.disconnected');
  }

  @override
  Future<void> sendMessage(String message) async {
    if (_advertising) {
      if (_subscribedCentrals.isEmpty) {
        throw StateError('bluetooth_no_notification_subscriber');
      }
      final characteristic = controlService.characteristics.last;
      for (final central in _subscribedCentrals.values.toList()) {
        final maxLength = await _peripheral.getMaximumNotifyLength(central);
        final frames = encodeControlFrames(message, maxLength);
        for (final frame in frames) {
          await _peripheral.notifyCharacteristic(
            central,
            characteristic,
            value: frame,
          );
          _log.debug('bluetooth', 'gatt.notification_sent', {
            'bytes': frame.length,
          });
        }
      }
      return;
    }
    final peripheral = _connectedPeripheral;
    final characteristic = _remoteCharacteristics[controlWriteUuid];
    if (peripheral == null || characteristic == null) {
      throw StateError('bluetooth_not_connected');
    }
    final maxLength = await _central.getMaximumWriteLength(
      peripheral,
      type: ble.GATTCharacteristicWriteType.withResponse,
    );
    final frames = encodeControlFrames(message, maxLength);
    _log.info('bluetooth', 'gatt.write_started', {
      'frameCount': frames.length,
      'maxFrameBytes': maxLength,
    });
    for (final frame in frames) {
      await _central.writeCharacteristic(
        peripheral,
        characteristic,
        value: frame,
        type: ble.GATTCharacteristicWriteType.withResponse,
      );
      _log.debug('bluetooth', 'gatt.write_completed', {'bytes': frame.length});
    }
  }

  bool _advertising = false;

  Future<void> _prepareManager(
    ble.BluetoothLowEnergyManager manager,
    String role,
  ) async {
    _log.info('bluetooth', 'adapter.check', {
      'role': role,
      'state': manager.state.name,
    });
    if (manager.state == ble.BluetoothLowEnergyState.unauthorized &&
        defaultTargetPlatform == TargetPlatform.android) {
      _log.info('bluetooth', 'permission.requested', {'role': role});
      final authorized = await manager.authorize();
      _log.info('bluetooth', 'permission.result', {
        'role': role,
        'granted': authorized,
      });
      if (!authorized) throw StateError('bluetooth_permission_denied');
      await _waitForState(manager);
    }
    var state = manager.state;
    if (state == ble.BluetoothLowEnergyState.unknown) {
      state = await _waitForState(manager);
    }
    if (state == ble.BluetoothLowEnergyState.unauthorized &&
        defaultTargetPlatform == TargetPlatform.android) {
      final authorized = await manager.authorize();
      if (!authorized) throw StateError('bluetooth_permission_denied');
      state = await _waitForState(manager);
    }
    if (state != ble.BluetoothLowEnergyState.poweredOn) {
      _log.warning('bluetooth', 'adapter.not_ready', {
        'role': role,
        'state': state.name,
      });
      throw StateError(
        state == ble.BluetoothLowEnergyState.poweredOff
            ? 'bluetooth_powered_off'
            : state == ble.BluetoothLowEnergyState.unsupported
            ? 'bluetooth_unsupported'
            : 'bluetooth_not_ready',
      );
    }
    _log.info('bluetooth', 'adapter.ready', {'role': role});
  }

  String _errorCode(Object error) {
    final text = error.toString();
    for (final code in [
      'bluetooth_permission_denied',
      'bluetooth_powered_off',
      'bluetooth_state_timeout',
      'bluetooth_unsupported',
      'bluetooth_no_notification_subscriber',
      'bluetooth_not_connected',
      'networksharing_gatt_service_incomplete',
    ]) {
      if (text.contains(code)) return code;
    }
    return error.runtimeType.toString();
  }

  Future<ble.BluetoothLowEnergyState> _waitForState(
    ble.BluetoothLowEnergyManager manager,
  ) async {
    final current = manager.state;
    if (current != ble.BluetoothLowEnergyState.unknown &&
        current != ble.BluetoothLowEnergyState.unauthorized) {
      return current;
    }
    final completer = Completer<ble.BluetoothLowEnergyState>();
    late final StreamSubscription<ble.BluetoothLowEnergyStateChangedEventArgs>
    subscription;
    subscription = manager.stateChanged.listen((event) {
      if (event.state != ble.BluetoothLowEnergyState.unknown &&
          event.state != ble.BluetoothLowEnergyState.unauthorized &&
          !completer.isCompleted) {
        completer.complete(event.state);
      }
    });
    try {
      return await completer.future.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      throw StateError('bluetooth_state_timeout');
    } finally {
      await subscription.cancel();
    }
  }

  BluetoothState _parseState(String? state) => switch (state) {
    'ready' => BluetoothState.ready,
    'poweredOff' => BluetoothState.poweredOff,
    'permissionDenied' => BluetoothState.permissionDenied,
    'unavailable' => BluetoothState.unavailable,
    _ => BluetoothState.failed,
  };
}
