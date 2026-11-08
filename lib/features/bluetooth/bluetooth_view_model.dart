import 'dart:async';

import 'package:flutter/foundation.dart';

import 'bluetooth_repository.dart';
import '../../data/app_logger.dart';

class BluetoothViewModel extends ChangeNotifier {
  BluetoothViewModel(this._repository);
  final BluetoothRepository _repository;
  BluetoothSnapshot? snapshot;
  List<BluetoothDevice> discoveredDevices = const [];
  bool checking = false;
  bool scanning = false;
  bool advertising = false;
  bool connecting = false;
  String? connectedDeviceId;
  String? transportError;
  String? lastMessage;
  StreamSubscription<String>? _messageSubscription;
  StreamSubscription<List<BluetoothDevice>>? _discoverySubscription;
  String? error;
  bool _disposed = false;
  int _operation = 0;
  final _log = AppLogger.instance;

  Future<void> inspect() async {
    if (_disposed || checking) return;
    _log.info('ui', 'bluetooth.inspect_clicked');
    final operation = ++_operation;
    checking = true;
    snapshot = null;
    error = null;
    notifyListeners();
    try {
      final result = await _repository.inspect().timeout(
        const Duration(seconds: 20),
      );
      if (!_disposed && operation == _operation) snapshot = result;
    } on TimeoutException {
      if (!_disposed && operation == _operation) error = '检查蓝牙超时，请重试。';
    } catch (caughtError) {
      _log.error('bluetooth', 'inspect.failed', {
        'errorType': caughtError.runtimeType.toString(),
      });
      if (!_disposed && operation == _operation) {
        error = '无法读取蓝牙状态，请检查权限后重试。';
      }
    } finally {
      if (!_disposed && operation == _operation) {
        checking = false;
        notifyListeners();
      }
    }
  }

  Future<void> scan() async {
    if (_disposed || scanning) return;
    _log.info('ui', 'bluetooth.scan_clicked');
    scanning = true;
    discoveredDevices = const [];
    error = null;
    await _discoverySubscription?.cancel();
    _discoverySubscription = _repository.discoveryResults.listen((devices) {
      discoveredDevices = devices;
      if (!_disposed) notifyListeners();
    });
    notifyListeners();
    try {
      discoveredDevices = await _repository.scan();
    } catch (error) {
      _log.error('bluetooth', 'scan.viewmodel_failed', {
        'errorType': error.runtimeType.toString(),
      });
      if (!_disposed) this.error = _bluetoothErrorMessage(error);
    } finally {
      await _discoverySubscription?.cancel();
      _discoverySubscription = null;
      if (!_disposed) {
        scanning = false;
        notifyListeners();
      }
    }
  }

  String _bluetoothErrorMessage(Object error) {
    final text = error.toString();
    if (text.contains('permission_denied')) {
      return '蓝牙权限被拒绝，请在系统设置中允许“附近设备”。';
    }
    if (text.contains('powered_off')) return '蓝牙已关闭，请先在系统设置中开启。';
    if (text.contains('state_timeout')) {
      return '蓝牙初始化超时，请确认适配器可用后重试。';
    }
    if (text.contains('unsupported')) return '此设备不支持 BLE。';
    return '蓝牙操作失败，请确认蓝牙已开启并允许权限后重试。';
  }

  Future<void> setAdvertising(bool enabled) async {
    if (_disposed || advertising == enabled) return;
    _log.info('ui', 'bluetooth.advertising_toggled', {'enabled': enabled});
    transportError = null;
    try {
      if (enabled) {
        await _repository.startAdvertising();
        advertising = true;
        _listenForMessages();
      } else {
        await _repository.stopAdvertising();
        advertising = false;
      }
    } catch (error) {
      _log.error('bluetooth', 'advertising.viewmodel_failed', {
        'errorType': error.runtimeType.toString(),
      });
      transportError = _bluetoothErrorMessage(error);
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> connect(BluetoothDevice device) async {
    if (_disposed || connecting || connectedDeviceId != null) return;
    _log.info('ui', 'bluetooth.connect_clicked');
    connecting = true;
    transportError = null;
    notifyListeners();
    try {
      await _repository.connect(device.id);
      if (_disposed) return;
      connectedDeviceId = device.id;
      _listenForMessages();
    } catch (error) {
      _log.error('bluetooth', 'connect.viewmodel_failed', {
        'errorType': error.runtimeType.toString(),
      });
      if (!_disposed) {
        transportError = '连接设备失败：${_bluetoothErrorMessage(error)}';
      }
    } finally {
      if (!_disposed) {
        connecting = false;
        notifyListeners();
      }
    }
  }

  Future<void> disconnect() async {
    if (_disposed) return;
    _log.info('ui', 'bluetooth.disconnect_clicked');
    try {
      await _repository.disconnect();
      connectedDeviceId = null;
      lastMessage = null;
    } catch (_) {
      transportError = '断开 BLE 连接失败。';
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> sendDiagnosticMessage() async {
    if (_disposed || (connectedDeviceId == null && !advertising)) return;
    _log.info('ui', 'bluetooth.diagnostic_send_clicked');
    final message =
        'transport-check:${DateTime.now().toUtc().toIso8601String()}';
    try {
      await _repository.sendMessage(message);
      transportError = null;
    } catch (error) {
      _log.error('bluetooth', 'diagnostic_send.failed', {
        'errorType': error.runtimeType.toString(),
      });
      final text = error.toString();
      transportError = text.contains('no_notification_subscriber')
          ? '当前没有订阅通知的对端，请确认对端已连接并重新订阅。'
          : '消息发送失败：${_bluetoothErrorMessage(error)}';
    }
    if (!_disposed) notifyListeners();
  }

  void _listenForMessages() {
    _messageSubscription ??= _repository.messages.listen(
      (message) {
        lastMessage = message;
        if (!_disposed) notifyListeners();
      },
      onError: (_) {
        transportError = '收到无法解析的 BLE 消息。';
        if (!_disposed) notifyListeners();
      },
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _operation++;
    _messageSubscription?.cancel();
    _discoverySubscription?.cancel();
    super.dispose();
  }
}
