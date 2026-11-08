import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bluetooth_repository.dart';
import '../../data/app_logger.dart';

class BluetoothViewModel extends ChangeNotifier {
  BluetoothViewModel(this._repository) {
    unawaited(_restorePairing());
  }
  final BluetoothRepository _repository;
  BluetoothSnapshot? snapshot;
  List<BluetoothDevice> discoveredDevices = const [];
  bool checking = false;
  bool scanning = false;
  bool advertising = false;
  bool connecting = false;
  bool pairingSystem = false;
  final Set<String> systemPairedDeviceIds = {};
  bool diagnosticSending = false;
  bool applicationPaired = false;
  String? _displayedPairingCode;
  Completer<bool>? _pairingResult;
  String? connectedDeviceId;
  String? pairedDeviceId;
  String? pairedDeviceName;
  String? diagnosticReceivedAt;
  String? transportError;
  String? lastMessage;
  StreamSubscription<String>? _messageSubscription;
  StreamSubscription<List<BluetoothDevice>>? _discoverySubscription;
  String? error;
  bool _disposed = false;
  int _operation = 0;
  final _log = AppLogger.instance;
  static const _platformChannel = MethodChannel('networksharing/bluetooth');

  BluetoothDevice? get connectedDevice {
    final id = connectedDeviceId;
    if (id == null) return null;
    for (final device in discoveredDevices) {
      if (device.id == id) return device;
    }
    return null;
  }

  bool get hasPersistedPairing => pairedDeviceId != null;

  Future<void> _restorePairing() async {
    try {
      final prefs = SharedPreferencesAsync();
      pairedDeviceId = await prefs.getString('networksharing.pairedDeviceId');
      pairedDeviceName = await prefs.getString(
        'networksharing.pairedDeviceName',
      );
      if (!_disposed) notifyListeners();
    } catch (_) {}
  }

  Future<void> _persistPairing(BluetoothDevice? device) async {
    try {
      final prefs = SharedPreferencesAsync();
      if (device == null) {
        await prefs.remove('networksharing.pairedDeviceId');
        await prefs.remove('networksharing.pairedDeviceName');
      } else {
        await prefs.setString('networksharing.pairedDeviceId', device.id);
        await prefs.setString('networksharing.pairedDeviceName', device.name);
      }
    } catch (_) {}
  }

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
    if (text.contains('location_disabled')) {
      return 'Android 11 及以下扫描蓝牙需要开启系统定位服务，请开启定位后重试。';
    }
    if (text.contains('powered_off')) return '蓝牙已关闭，请先在系统设置中开启。';
    if (text.contains('state_timeout')) {
      return '蓝牙初始化超时，请确认适配器可用后重试。';
    }
    if (text.contains('unsupported')) return '此设备不支持 BLE。';
    if (text.contains('windows_peripheral_role_unavailable')) {
      return '此电脑的蓝牙适配器不支持 Peripheral/GATT 广播角色，无法被另一端发现。';
    }
    if (text.contains('windows_pair_in_settings_then_connect')) {
      return '请先在 Windows“设置 > 蓝牙和设备”中与目标手机完成系统蓝牙配对，再返回此处扫描连接。';
    }
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
        await _setBackgroundTransport(true);
      } else {
        await _repository.stopAdvertising();
        advertising = false;
        if (connectedDeviceId == null) await _setBackgroundTransport(false);
      }
    } catch (error) {
      final code = _diagnosticError(error);
      _log.error('bluetooth', 'advertising.viewmodel_failed', {'error': code});
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
      await _setBackgroundTransport(true);
    } catch (error) {
      _log.error('bluetooth', 'connect.viewmodel_failed', {
        'error': _diagnosticError(error),
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

  Future<void> pairSystemDevice(BluetoothDevice device) async {
    if (_disposed || pairingSystem) return;
    _log.info('ui', 'bluetooth.system_pair_clicked');
    pairingSystem = true;
    transportError = null;
    notifyListeners();
    try {
      await _repository.pairSystemDevice(device.id);
      systemPairedDeviceIds.add(device.id);
      transportError = '系统蓝牙配对完成。现在可通过 BLE 连接并验证应用配对码。';
      _log.info('bluetooth', 'system_pair.completed');
    } catch (error) {
      _log.error('bluetooth', 'system_pair.failed', {
        'error': _diagnosticError(error),
      });
      transportError = '系统蓝牙配对失败：${_bluetoothErrorMessage(error)}';
    } finally {
      pairingSystem = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> disconnect() async {
    if (_disposed) return;
    _log.info('ui', 'bluetooth.disconnect_clicked');
    try {
      await _repository.disconnect();
      connectedDeviceId = null;
      applicationPaired = false;
      lastMessage = null;
      if (!advertising) await _setBackgroundTransport(false);
    } catch (_) {
      transportError = '断开 BLE 连接失败。';
    }
    _displayedPairingCode = null;
    applicationPaired = false;
    if (!_disposed) notifyListeners();
  }

  Future<void> _setBackgroundTransport(bool enabled) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _platformChannel.invokeMethod<bool>('setBackgroundTransport', {
        'enabled': enabled,
      });
      _log.info('bluetooth', 'background_transport.updated', {
        'enabled': enabled,
      });
    } catch (error) {
      _log.error('bluetooth', 'background_transport.failed', {
        'enabled': enabled,
        'errorType': error.runtimeType.toString(),
      });
      transportError = '后台蓝牙服务无法启动，请检查通知和附近设备权限。';
    }
  }

  void setDisplayedPairingCode(String? code) {
    if (_displayedPairingCode != code) applicationPaired = false;
    _displayedPairingCode = code;
  }

  Future<bool> authenticatePairingCode(String code) async {
    if (_disposed || connectedDeviceId == null || _pairingResult != null) {
      return false;
    }
    final result = Completer<bool>();
    _pairingResult = result;
    _listenForMessages();
    _log.info('pairing', 'authentication.requested', {
      'codeLength': code.length,
    });
    try {
      await _repository.sendMessage(
        jsonEncode({'type': 'pairing_auth_request', 'code': code}),
      );
      final success = await result.future.timeout(const Duration(seconds: 15));
      applicationPaired = success;
      if (success) {
        pairedDeviceId = connectedDeviceId;
        pairedDeviceName = connectedDevice?.name;
        unawaited(_persistPairing(connectedDevice));
      }
      _log.info(
        'pairing',
        success ? 'authentication.accepted' : 'authentication.rejected',
      );
      notifyListeners();
      return success;
    } on TimeoutException {
      _log.warning('pairing', 'authentication.timeout');
      return false;
    } catch (error) {
      _log.error('pairing', 'authentication.failed', {
        'errorType': error.runtimeType.toString(),
      });
      return false;
    } finally {
      if (identical(_pairingResult, result)) _pairingResult = null;
    }
  }

  Future<void> _handleProtocolMessage(String message) async {
    if (!message.startsWith('{')) return;
    try {
      final decoded = jsonDecode(message);
      if (decoded is! Map<String, dynamic>) return;
      if (decoded['type'] == 'pairing_auth_request') {
        final code = decoded['code'];
        final accepted =
            code is String &&
            RegExp(r'^[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{6}$').hasMatch(code) &&
            _displayedPairingCode != null &&
            code == _displayedPairingCode;
        _log.info(
          'pairing',
          accepted ? 'authentication.accepted' : 'authentication.rejected',
        );
        if (accepted) {
          applicationPaired = true;
          pairedDeviceId = connectedDeviceId;
          pairedDeviceName = connectedDevice?.name;
          unawaited(_persistPairing(connectedDevice));
        }
        await _repository.sendMessage(
          jsonEncode({'type': 'pairing_auth_result', 'success': accepted}),
        );
        notifyListeners();
      } else if (decoded['type'] == 'pairing_auth_result') {
        if (!(_pairingResult?.isCompleted ?? true)) {
          _pairingResult!.complete(decoded['success'] == true);
        }
      }
    } catch (error) {
      _log.warning('pairing', 'authentication.message_invalid', {
        'errorType': error.runtimeType.toString(),
      });
    }
  }

  Future<void> sendDiagnosticMessage() async {
    if (_disposed ||
        diagnosticSending ||
        (connectedDeviceId == null && !advertising)) {
      return;
    }
    diagnosticSending = true;
    _log.info('ui', 'bluetooth.diagnostic_send_clicked');
    notifyListeners();
    final message =
        'transport-check:${DateTime.now().toUtc().toIso8601String()}';
    try {
      await _repository.sendMessage(message);
      transportError = null;
    } catch (error) {
      _log.error('bluetooth', 'diagnostic_send.failed', {
        'error': _diagnosticError(error),
      });
      final text = error.toString();
      transportError = text.contains('no_notification_subscriber')
          ? '当前没有订阅通知的对端，请确认对端已连接并重新订阅。'
          : '消息发送失败（${_diagnosticError(error)}）：${_bluetoothErrorMessage(error)}';
    }
    diagnosticSending = false;
    if (!_disposed) notifyListeners();
  }

  String _diagnosticError(Object error) {
    final text = error.toString();
    return text.length > 320 ? text.substring(0, 320) : text;
  }

  void _listenForMessages() {
    _messageSubscription ??= _repository.messages.listen(
      (message) {
        unawaited(_handleProtocolMessage(message));
        if (message.startsWith('transport-check:')) {
          diagnosticReceivedAt = DateTime.now().toLocal().toString();
          _log.info('bluetooth', 'diagnostic.received');
        }
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
    if (!(_pairingResult?.isCompleted ?? true)) _pairingResult!.complete(false);
    super.dispose();
  }
}
