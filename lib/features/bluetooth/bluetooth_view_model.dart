import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/http_connectivity_repository.dart';
import '../../data/debug_notifications.dart';
import '../../data/platform_network_control.dart';
import '../../domain/connectivity.dart';

import 'bluetooth_repository.dart';
import '../../data/app_logger.dart';

class BluetoothViewModel extends ChangeNotifier {
  BluetoothViewModel(
    this._repository, {
    ConnectivityRepository? connectivityRepository,
    this.heartbeatInterval = const Duration(seconds: 10),
    this.peerTimeout = const Duration(seconds: 30),
    this.reconnectDelay = const Duration(seconds: 5),
    this.initialReconnectDelay = const Duration(seconds: 2),
    this.initialNetworkDelay = const Duration(seconds: 5),
    this.autoRecoverOnRestore = true,
  }) : _connectivityRepository =
           connectivityRepository ?? HttpConnectivityRepository() {
    _pairingLoadFuture = _restorePairing();
    DebugNotifications.instance.onHotspotResponse =
        _handleHotspotNotificationAction;
  }
  final BluetoothRepository _repository;
  final _sharingMessages = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get sharingMessages => _sharingMessages.stream;

  Future<void> sendSharingMessage(Map<String, dynamic> message) async {
    if (_disposed || !applicationPaired || !peerOnline) {
      throw StateError('已配对设备当前未连接');
    }
    await _repository.sendMessage(jsonEncode(message));
  }

  Timer? _runtimeTimer;
  bool _runtimeBusy = false;
  bool _backgroundEnabled = true;

  Future<void> startRuntime() async {
    _runtimeTimer ??= Timer.periodic(const Duration(seconds: 20), (_) {
      unawaited(recoverConnection());
    });
    if (defaultTargetPlatform == TargetPlatform.windows && !advertising) {
      await setAdvertising(true);
    }
    await recoverConnection();
  }

  Future<void> setBackgroundEnabled(bool enabled) async {
    if (_backgroundEnabled == enabled) return;
    _backgroundEnabled = enabled;
    await _setBackgroundTransport(enabled);
  }

  Future<void> recoverConnection() async {
    await _pairingLoadFuture;
    if (_disposed ||
        _runtimeBusy ||
        !_autoReconnect ||
        applicationPaired ||
        (connectedDeviceId != null && !pairingRestoring)) {
      return;
    }
    _runtimeBusy = true;
    try {
      _log.info('bluetooth', 'runtime.recovery_check');
      if (defaultTargetPlatform == TargetPlatform.windows) {
        if (!advertising) await setAdvertising(true);
      } else if (defaultTargetPlatform == TargetPlatform.android &&
          _backgroundEnabled &&
          pairedDeviceId != null &&
          !pairingRestoring) {
        if (_backgroundEnabled) await _setBackgroundTransport(true);
        await _attemptReconnect();
      }
    } finally {
      _runtimeBusy = false;
    }
  }

  final ConnectivityRepository _connectivityRepository;
  final Duration heartbeatInterval;
  final Duration peerTimeout;
  final Duration reconnectDelay;
  final Duration initialReconnectDelay;
  final Duration initialNetworkDelay;
  final bool autoRecoverOnRestore;
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
  String? _resumeToken;
  final Map<String, String> _resumeTokensByDevice = {};
  bool pairingRestored = false;
  bool pairingRestoring = false;
  String? diagnosticReceivedAt;
  String? transportError;
  String? lastMessage;
  String? lastNetworkProbeResult;
  String? lastReceivedWifiCredentials;
  String? peerNetworkStatus;
  bool peerOnline = false;
  bool peerHotspotRequestPending = false;
  DateTime? peerLastSeen;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  bool _reconnecting = false;
  bool _autoReconnect = true;
  Timer? _initialNetworkTimer;
  Timer? _hotspotRequestExpiryTimer;
  bool _initialNetworkSent = false;
  String? _pendingHotspotRequestId;
  DateTime? _pendingHotspotRequestAt;
  String? _outgoingHotspotRequestId;
  String? hotspotRequestStatus;
  String? localHotspotStatus;
  bool hotspotBusy = false;
  late final Future<void> _pairingLoadFuture;
  String? receivedWifiSsid;
  String? receivedWifiPassword;
  String? wifiTransferStatus;
  String? _wifiTransferId;
  Timer? _wifiTransferTimer;
  StreamSubscription<String>? _messageSubscription;
  StreamSubscription<List<BluetoothDevice>>? _discoverySubscription;
  String? error;
  bool _disposed = false;
  int _operation = 0;
  final _log = AppLogger.instance;
  static const _platformChannel = MethodChannel('networksharing/bluetooth');

  String _createResumeToken() {
    final random = Random.secure();
    return base64UrlEncode(List<int>.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }

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
      final isWindows = defaultTargetPlatform == TargetPlatform.windows;
      pairedDeviceId = await prefs.getString(
        isWindows
            ? 'networksharing.pairedDeviceId.windows'
            : 'networksharing.pairedDeviceId',
      );
      pairedDeviceName = await prefs.getString(
        isWindows
            ? 'networksharing.pairedDeviceName.windows'
            : 'networksharing.pairedDeviceName',
      );
      if (defaultTargetPlatform == TargetPlatform.windows) {
        _resumeToken = await prefs.getString(
          'networksharing.pairResumeToken.windows',
        );
      } else {
        _resumeToken = await prefs.getString('networksharing.pairResumeToken');
      }
      final tokenMap = await prefs.getString(
        defaultTargetPlatform == TargetPlatform.windows
            ? 'networksharing.peerResumeTokens.windows'
            : 'networksharing.peerResumeTokens',
      );
      if (tokenMap != null) {
        final decoded = jsonDecode(tokenMap);
        if (decoded is Map<String, dynamic>) {
          _resumeTokensByDevice.addAll(
            decoded.map((key, value) => MapEntry(key, value.toString())),
          );
        }
      }
      if (pairedDeviceId != null && _resumeToken != null) {
        _resumeTokensByDevice.putIfAbsent(pairedDeviceId!, () => _resumeToken!);
      }
      pairingRestored = pairedDeviceId != null && _resumeToken != null;
      if (autoRecoverOnRestore &&
          pairingRestored &&
          !_disposed &&
          defaultTargetPlatform == TargetPlatform.android) {
        _reconnectTimer = Timer(initialReconnectDelay, _attemptReconnect);
      }
      if (!_disposed) notifyListeners();
    } catch (error) {
      _log.warning('pairing', 'restore.failed', {
        'errorType': error.runtimeType.toString(),
      });
    }
  }

  Future<void> _persistPairing(BluetoothDevice? device) async {
    try {
      final prefs = SharedPreferencesAsync();
      if (device == null) {
        final suffix = defaultTargetPlatform == TargetPlatform.windows
            ? '.windows'
            : '';
        await prefs.remove('networksharing.pairedDeviceId$suffix');
        await prefs.remove('networksharing.pairedDeviceName$suffix');
      } else {
        final suffix = defaultTargetPlatform == TargetPlatform.windows
            ? '.windows'
            : '';
        await prefs.setString(
          'networksharing.pairedDeviceId$suffix',
          device.id,
        );
        await prefs.setString(
          'networksharing.pairedDeviceName$suffix',
          device.name,
        );
        if (_resumeToken != null) {
          await prefs.setString(
            defaultTargetPlatform == TargetPlatform.windows
                ? 'networksharing.pairResumeToken.windows'
                : 'networksharing.pairResumeToken',
            _resumeToken!,
          );
        }
      }
      await prefs.setString(
        defaultTargetPlatform == TargetPlatform.windows
            ? 'networksharing.peerResumeTokens.windows'
            : 'networksharing.peerResumeTokens',
        jsonEncode(_resumeTokensByDevice),
      );
    } catch (error) {
      _log.error('pairing', 'persistence.failed', {
        'errorType': error.runtimeType.toString(),
      });
    }
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
    await _pairingLoadFuture;
    if (_disposed) return;
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
    await _pairingLoadFuture;
    if (_disposed) return;
    _autoReconnect = true;
    _log.info('ui', 'bluetooth.connect_clicked');
    connecting = true;
    transportError = null;
    notifyListeners();
    try {
      await _repository.connect(device.id).timeout(const Duration(seconds: 30));
      if (_disposed) return;
      connectedDeviceId = device.id;
      _resumeToken = _resumeTokensByDevice[device.id];
      applicationPaired = false;
      pairingRestoring = _resumeToken != null;
      _listenForMessages();
      await _setBackgroundTransport(true);
      if (_resumeToken != null) {
        unawaited(_resumeApplicationPairing());
      }
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

  Future<void> _resumeApplicationPairing() async {
    if (_resumeToken == null ||
        connectedDeviceId == null ||
        _pairingResult != null) {
      return;
    }
    final result = Completer<bool>();
    _pairingResult = result;
    _log.info('pairing', 'resume.requested');
    try {
      await _repository.sendMessage(
        jsonEncode({'type': 'pairing_resume_request', 'token': _resumeToken}),
      );
      final accepted = await result.future.timeout(const Duration(seconds: 8));
      applicationPaired = accepted;
      pairingRestored = accepted;
      if (accepted) _startPeerMonitoring();
      if (!accepted) {
        transportError = '已保存的配对凭据未被对端接受；记录已保留，请重新输入配对码验证。';
        _log.warning('pairing', 'resume.rejected_pairing_preserved');
      }
      _log.info('pairing', accepted ? 'resume.accepted' : 'resume.rejected');
    } on TimeoutException {
      _log.warning('pairing', 'resume.timeout');
      unawaited(_retryConnectionAfterResumeTimeout());
    } catch (error) {
      _log.error('pairing', 'resume.failed', {
        'errorType': error.runtimeType.toString(),
      });
      unawaited(_retryConnectionAfterResumeTimeout());
    } finally {
      pairingRestoring = false;
      if (identical(_pairingResult, result)) _pairingResult = null;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _retryConnectionAfterResumeTimeout() async {
    if (_disposed || !_autoReconnect) return;
    try {
      await _repository.disconnect();
    } catch (_) {}
    if (_disposed) return;
    connectedDeviceId = null;
    applicationPaired = false;
    _stopPeerMonitoring();
    _reconnectTimer = Timer(reconnectDelay, _attemptReconnect);
    notifyListeners();
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
    _autoReconnect = false;
    _log.info('ui', 'bluetooth.disconnect_clicked');
    try {
      await _repository.disconnect();
      connectedDeviceId = null;
      _stopPeerMonitoring();
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
    if (enabled && !_backgroundEnabled) return;
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
    _displayedPairingCode = code;
  }

  Future<bool> authenticatePairingCode(String code) async {
    await _pairingLoadFuture;
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
      if (_disposed) return false;
      applicationPaired = success;
      if (success) {
        _startPeerMonitoring();
        pairingRestored = true;
        pairedDeviceId = connectedDeviceId;
        pairedDeviceName = connectedDevice?.name ?? 'Windows 电脑';
        if (pairedDeviceId != null) {
          _resumeTokensByDevice[pairedDeviceId!] = _resumeToken!;
          await _persistPairing(
            BluetoothDevice(id: pairedDeviceId!, name: pairedDeviceName!),
          );
        }
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
      if (_disposed) return;
      if (applicationPaired) {
        peerLastSeen = DateTime.now();
        peerOnline = true;
      }
      final type = decoded['type'];
      if (type is String && type.startsWith('share_')) {
        if (applicationPaired) _sharingMessages.add(decoded);
        return;
      }
      if (!applicationPaired &&
          const {
            'hotspot_request',
            'hotspot_request_response',
            'hotspot_operation_result',
            'notification_test',
            'debug_wifi_credentials',
            'debug_wifi_connection_result',
            'debug_wifi_credentials_ack',
            'network_probe_result',
            'network_probe_ack',
            'peer_network_status',
          }.contains(type)) {
        _log.warning('bluetooth', 'protocol.unauthenticated_message_rejected', {
          'type': type,
        });
        return;
      }
      if (decoded['type'] == 'pairing_auth_request') {
        await _pairingLoadFuture;
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
          _startPeerMonitoring();
          pairingRestored = true;
          _resumeToken ??= _createResumeToken();
          pairedDeviceId ??= connectedDeviceId ?? 'windows-central';
          pairedDeviceName ??= connectedDevice?.name ?? '已配对手机';
          _resumeTokensByDevice[pairedDeviceId!] = _resumeToken!;
          await _persistPairing(
            BluetoothDevice(id: pairedDeviceId!, name: pairedDeviceName!),
          );
        }
        await _repository.sendMessage(
          jsonEncode({
            'type': 'pairing_auth_result',
            'success': accepted,
            if (accepted) 'resumeToken': _resumeToken,
          }),
        );
        notifyListeners();
      } else if (decoded['type'] == 'pairing_resume_request') {
        await _pairingLoadFuture;
        final token = decoded['token'];
        final expectedToken = connectedDeviceId == null
            ? _resumeTokensByDevice[pairedDeviceId] ?? _resumeToken
            : _resumeTokensByDevice[connectedDeviceId] ?? _resumeToken;
        final accepted =
            token is String && expectedToken != null && token == expectedToken;
        applicationPaired = accepted;
        if (accepted) _startPeerMonitoring();
        await _repository.sendMessage(
          jsonEncode({'type': 'pairing_resume_result', 'success': accepted}),
        );
        _log.info('pairing', accepted ? 'resume.accepted' : 'resume.rejected');
        notifyListeners();
      } else if (decoded['type'] == 'network_probe_result') {
        lastNetworkProbeResult = decoded['online'] == true
            ? '对端报告：互联网可用'
            : '对端报告：无法确认互联网连通';
        _log.info('debug', 'network_probe.peer_result_received', {
          'online': decoded['online'] == true,
        });
        await _repository.sendMessage(
          jsonEncode({'type': 'network_probe_ack', 'received': true}),
        );
        notifyListeners();
      } else if (decoded['type'] == 'network_probe_ack') {
        lastNetworkProbeResult = '对端已收到网络检测结果';
        _log.info('debug', 'network_probe.peer_ack_received');
        notifyListeners();
      } else if (decoded['type'] == 'hotspot_request') {
        final requestId = decoded['requestId'];
        if (requestId is! String || requestId.isEmpty) return;
        peerHotspotRequestPending = true;
        _pendingHotspotRequestId = requestId;
        _pendingHotspotRequestAt = DateTime.now();
        _hotspotRequestExpiryTimer?.cancel();
        _hotspotRequestExpiryTimer = Timer(const Duration(minutes: 2), () {
          if (_pendingHotspotRequestId != requestId) return;
          peerHotspotRequestPending = false;
          _pendingHotspotRequestId = null;
          _pendingHotspotRequestAt = null;
          if (!_disposed) notifyListeners();
          _log.info('debug', 'hotspot.request_expired');
        });
        unawaited(_notifyPeerHotspotRequest(requestId));
        notifyListeners();
      } else if (decoded['type'] == 'hotspot_request_response') {
        if (decoded['requestId'] != _outgoingHotspotRequestId) return;
        hotspotRequestStatus = decoded['accepted'] == true
            ? '对端已确认，正在开启热点。'
            : '对端拒绝了开启热点请求。';
        _log.info('debug', 'hotspot.peer_response_received', {
          'accepted': decoded['accepted'] == true,
        });
        notifyListeners();
      } else if (decoded['type'] == 'hotspot_operation_result') {
        if (decoded['requestId'] != _outgoingHotspotRequestId) return;
        hotspotRequestStatus = decoded['success'] == true
            ? '对端热点已启动，等待接收网络信息。'
            : '对端启动热点失败，请查看对端日志。';
        _log.info('debug', 'hotspot.peer_operation_result', {
          'success': decoded['success'] == true,
        });
        notifyListeners();
      } else if (decoded['type'] == 'notification_test') {
        unawaited(
          DebugNotifications.instance
              .show(
                'NetworkSharing 通知测试',
                decoded['body']?.toString() ?? '收到对端测试通知。',
              )
              .catchError((Object error) {
                _log.warning('notification', 'peer_test.failed', {
                  'errorType': error.runtimeType.toString(),
                });
              }),
        );
      } else if (decoded['type'] == 'heartbeat') {
        if (!applicationPaired) return;
        if (_heartbeatTimer == null) _startPeerMonitoring();
        peerLastSeen = DateTime.now();
        peerOnline = true;
        await _repository.sendMessage(jsonEncode({'type': 'heartbeat_ack'}));
        notifyListeners();
      } else if (decoded['type'] == 'heartbeat_ack') {
        if (!applicationPaired) return;
        peerLastSeen = DateTime.now();
        peerOnline = true;
        notifyListeners();
      } else if (decoded['type'] == 'peer_network_status') {
        peerNetworkStatus = decoded['online'] == true ? '互联网可用' : '互联网不可用';
        _log.info('debug', 'peer.network_status_received', {
          'online': decoded['online'] == true,
        });
        notifyListeners();
      } else if (decoded['type'] == 'debug_wifi_credentials') {
        final ssid = decoded['ssid'];
        final password = decoded['password'];
        if (ssid is String && password is String) {
          receivedWifiSsid = ssid;
          receivedWifiPassword = password;
          lastReceivedWifiCredentials = '$ssid / ••••••••';
          wifiTransferStatus = '已收到对端 Wi-Fi 信息。';
          _log.warning('debug', 'wifi.credentials_received', {
            'ssidLength': ssid.length,
            'passwordLength': password.length,
          });
          notifyListeners();
          await _repository.sendMessage(
            jsonEncode({
              'type': 'debug_wifi_credentials_ack',
              'transferId': decoded['transferId'],
            }),
          );
        }
      } else if (decoded['type'] == 'debug_wifi_credentials_ack') {
        if (_wifiTransferId != decoded['transferId']) return;
        _wifiTransferTimer?.cancel();
        _wifiTransferId = null;
        wifiTransferStatus = '对端已确认收到 Wi-Fi 信息。';
        _log.info('debug', 'wifi.credentials_ack_received');
        notifyListeners();
      } else if (decoded['type'] == 'debug_wifi_connection_result') {
        hotspotRequestStatus = decoded['success'] == true
            ? '对端已连接到共享 Wi-Fi。'
            : '对端连接 Wi-Fi 失败。';
        _log.info('debug', 'wifi.peer_connection_result', {
          'success': decoded['success'] == true,
        });
        notifyListeners();
      } else if (decoded['type'] == 'pairing_auth_result') {
        if (!(_pairingResult?.isCompleted ?? true)) {
          final token = decoded['resumeToken'];
          if (decoded['success'] == true &&
              (token is! String || token.isEmpty)) {
            _log.warning('pairing', 'authentication.missing_resume_token');
            _pairingResult!.complete(false);
            return;
          }
          if (decoded['success'] == true) {
            _resumeToken = decoded['resumeToken'] as String?;
            pairingRestored = _resumeToken != null;
            if (pairedDeviceId != null && _resumeToken != null) {
              _resumeTokensByDevice[pairedDeviceId!] = _resumeToken!;
            }
          }
          _pairingResult!.complete(decoded['success'] == true);
        }
      } else if (decoded['type'] == 'pairing_resume_result' &&
          _pairingResult != null &&
          !_pairingResult!.isCompleted) {
        _pairingResult!.complete(decoded['success'] == true);
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

  Future<void> runNetworkProbe() async {
    _log.info('debug', 'network_probe.started');
    try {
      final result = await _connectivityRepository.check();
      lastNetworkProbeResult = result.state == ConnectivityState.online
          ? '互联网可用：${result.reachableHosts.join('、')}'
          : '百度和 Google 均无法连接';
      if (connectedDeviceId != null || advertising) {
        await _repository.sendMessage(
          jsonEncode({
            'type': 'network_probe_result',
            'online': result.state == ConnectivityState.online,
            'reachableHosts': result.reachableHosts.toList(),
            'checkedAt': result.checkedAt.toUtc().toIso8601String(),
          }),
        );
        _log.info('debug', 'network_probe.result_sent', {
          'online': result.state == ConnectivityState.online,
          'reachableHostCount': result.reachableHosts.length,
        });
      }
    } catch (error) {
      lastNetworkProbeResult = '检测失败';
      _log.error('debug', 'network_probe.failed', {
        'errorType': error.runtimeType.toString(),
      });
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> runLocalNetworkProbe() async {
    _log.info('debug', 'network_probe.local_started');
    try {
      final result = await _connectivityRepository.check();
      lastNetworkProbeResult = result.state == ConnectivityState.online
          ? '互联网可用：'
          : '百度和 Google 均无法连接';
      _log.info('debug', 'network_probe.local_result', {
        'online': result.state == ConnectivityState.online,
        'reachableHostCount': result.reachableHosts.length,
      });
    } catch (error) {
      lastNetworkProbeResult = '检测失败';
      _log.error('debug', 'network_probe.local_failed', {
        'errorType': error.runtimeType.toString(),
      });
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> sendDebugWifiCredentials(String ssid, String password) async {
    if ((connectedDeviceId == null && !advertising) || !applicationPaired) {
      throw StateError('需要先建立并恢复应用配对连接');
    }
    _log.warning('debug', 'wifi.credentials_send_requested', {
      'ssidLength': ssid.length,
      'passwordLength': password.length,
    });
    final transferId = _createResumeToken().substring(0, 16);
    _wifiTransferId = transferId;
    wifiTransferStatus = '正在发送 Wi-Fi 信息。';
    await _repository.sendMessage(
      jsonEncode({
        'type': 'debug_wifi_credentials',
        'ssid': ssid,
        'password': password,
        'transferId': transferId,
      }),
    );
    _log.warning('debug', 'wifi.credentials_sent');
    if (_wifiTransferId != transferId) return;
    _wifiTransferTimer?.cancel();
    _wifiTransferTimer = Timer(const Duration(seconds: 8), () {
      if (_wifiTransferId != transferId) return;
      wifiTransferStatus = '已发送，但尚未收到对端确认；可重新发送。';
      _log.warning('debug', 'wifi.credentials_ack_timeout');
      if (!_disposed) notifyListeners();
    });
  }

  void _startPeerMonitoring() {
    _stopPeerMonitoring();
    peerOnline = true;
    peerLastSeen = DateTime.now();
    _initialNetworkSent = false;
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) async {
      if (_disposed ||
          (connectedDeviceId == null && !advertising) ||
          !applicationPaired) {
        return;
      }
      try {
        await _repository.sendMessage(jsonEncode({'type': 'heartbeat'}));
      } catch (error) {
        _log.warning('bluetooth', 'heartbeat.send_failed', {
          'errorType': error.runtimeType.toString(),
        });
      }
      final last = peerLastSeen;
      peerOnline =
          last != null && DateTime.now().difference(last) < peerTimeout;
      if (!peerOnline && !_reconnecting) {
        applicationPaired = false;
        peerHotspotRequestPending = false;
        _pendingHotspotRequestId = null;
        peerNetworkStatus = null;
        unawaited(_attemptReconnect());
      }
      if (!_disposed) notifyListeners();
    });
    _initialNetworkTimer = Timer(
      initialNetworkDelay,
      _sendInitialNetworkStatus,
    );
    notifyListeners();
  }

  Future<void> _sendInitialNetworkStatus() async {
    if (_disposed ||
        _initialNetworkSent ||
        (connectedDeviceId == null && !advertising) ||
        !applicationPaired) {
      return;
    }
    _initialNetworkSent = true;
    try {
      final result = await _connectivityRepository.check();
      if (_disposed || !applicationPaired) return;
      await _repository.sendMessage(
        jsonEncode({
          'type': 'peer_network_status',
          'online': result.state == ConnectivityState.online,
          'reachableHosts': result.reachableHosts.toList(),
        }),
      );
      _log.info('debug', 'peer.network_status_sent', {
        'online': result.state == ConnectivityState.online,
      });
    } catch (error) {
      _log.error('debug', 'peer.network_status_failed', {
        'errorType': error.runtimeType.toString(),
      });
    }
  }

  void _stopPeerMonitoring() {
    _heartbeatTimer?.cancel();
    _initialNetworkTimer?.cancel();
    _hotspotRequestExpiryTimer?.cancel();
    _wifiTransferTimer?.cancel();
    _wifiTransferId = null;
    peerHotspotRequestPending = false;
    _pendingHotspotRequestId = null;
    _pendingHotspotRequestAt = null;
    _heartbeatTimer = null;
    _initialNetworkTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    peerOnline = false;
  }

  Future<void> requestPeerHotspot() async {
    if ((connectedDeviceId == null && !advertising) || !applicationPaired) {
      throw StateError('需要先建立并恢复应用配对连接');
    }
    final requestId = _createResumeToken().substring(0, 16);
    _outgoingHotspotRequestId = requestId;
    await _repository.sendMessage(
      jsonEncode({'type': 'hotspot_request', 'requestId': requestId}),
    );
    _log.info('debug', 'hotspot.peer_request_sent');
  }

  Future<void> sendNotificationTest() async {
    await DebugNotifications.instance.show('NetworkSharing 通知测试', '本机通知功能正常。');
    if ((connectedDeviceId != null || advertising) && applicationPaired) {
      await _repository.sendMessage(
        jsonEncode({'type': 'notification_test', 'body': '已配对设备发送的通知测试。'}),
      );
    }
  }

  Future<void> _notifyPeerHotspotRequest(String requestId) async {
    try {
      await DebugNotifications.instance.show(
        '热点连接请求',
        '已配对设备请求开启本机热点。',
        hotspotRequestId: requestId,
      );
    } catch (error) {
      _log.warning('debug', 'hotspot.notification_failed', {
        'errorType': error.runtimeType.toString(),
      });
    }
  }

  Future<void> respondToPeerHotspot(bool accepted) async {
    final requestId = _pendingHotspotRequestId;
    if (_disposed ||
        !applicationPaired ||
        requestId == null ||
        (connectedDeviceId == null && !advertising)) {
      return;
    }
    final requestedAt = _pendingHotspotRequestAt;
    if (requestedAt == null ||
        DateTime.now().difference(requestedAt) > const Duration(minutes: 2)) {
      peerHotspotRequestPending = false;
      _pendingHotspotRequestId = null;
      if (!_disposed) notifyListeners();
      return;
    }
    peerHotspotRequestPending = false;
    _pendingHotspotRequestId = null;
    _hotspotRequestExpiryTimer?.cancel();
    await _repository.sendMessage(
      jsonEncode({
        'type': 'hotspot_request_response',
        'requestId': requestId,
        'accepted': accepted,
      }),
    );
    notifyListeners();
    if (accepted) {
      final success = await controlHotspot('startHotspot');
      await _repository.sendMessage(
        jsonEncode({
          'type': 'hotspot_operation_result',
          'requestId': requestId,
          'success': success,
        }),
      );
    }
  }

  Future<void> _handleHotspotNotificationAction(
    String requestId,
    bool accepted,
  ) async {
    if (_pendingHotspotRequestId != requestId) return;
    await respondToPeerHotspot(accepted);
  }

  Future<bool> controlHotspot(String operation) async {
    if (hotspotBusy || _disposed) return false;
    hotspotBusy = true;
    notifyListeners();
    try {
      final result = await PlatformNetworkControl().execute(operation);
      localHotspotStatus = result['message']?.toString();
      final ssid = result['ssid']?.toString();
      final password = result['password']?.toString();
      if (operation != 'stopHotspot' &&
          result['enabled'] == true &&
          ssid != null &&
          ssid.isNotEmpty &&
          password != null &&
          applicationPaired) {
        await sendDebugWifiCredentials(ssid, password);
        localHotspotStatus = '热点信息已读取并发送给对端。';
      } else if (operation != 'stopHotspot') {
        _log.warning('debug', 'hotspot.credentials_unavailable');
      }
      return true;
    } catch (error) {
      localHotspotStatus = error.toString();
      _log.error('debug', 'hotspot.request_start_failed', {
        'errorType': error.runtimeType.toString(),
      });
      return false;
    } finally {
      hotspotBusy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _attemptReconnect() async {
    if (!_disposed && _autoReconnect && (connecting || scanning)) {
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(reconnectDelay, _attemptReconnect);
      return;
    }
    if (_disposed ||
        !_autoReconnect ||
        _reconnecting ||
        connecting ||
        scanning ||
        pairedDeviceId == null ||
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    _reconnecting = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final targetId = pairedDeviceId;
    try {
      try {
        await _repository.disconnect().timeout(const Duration(seconds: 5));
      } catch (_) {}
      connectedDeviceId = null;
      applicationPaired = false;
      _stopPeerMonitoring();
      if (_disposed || !_autoReconnect) return;
      _log.info('bluetooth', 'reconnect.scan_started');
      final devices = await _repository
          .scan(duration: const Duration(seconds: 5))
          .timeout(const Duration(seconds: 25));
      BluetoothDevice? target;
      for (final device in devices) {
        if (device.id == targetId) {
          target = device;
          break;
        }
      }
      if (_disposed || !_autoReconnect) return;
      if (target != null) {
        _log.info('bluetooth', 'reconnect.target_found');
        await connect(target);
      } else {
        _log.info('bluetooth', 'reconnect.target_not_found');
      }
    } catch (error) {
      _log.warning('bluetooth', 'reconnect.failed', {
        'errorType': error.runtimeType.toString(),
      });
    } finally {
      _reconnecting = false;
      if (connectedDeviceId == null && !_disposed && _autoReconnect) {
        _reconnectTimer?.cancel();
        _reconnectTimer = Timer(reconnectDelay, _attemptReconnect);
      }
    }
  }

  String _diagnosticError(Object error) {
    final text = error.toString();
    return text.length > 320 ? text.substring(0, 320) : text;
  }

  Future<void> reportWifiConnectionResult(bool success) async {
    if ((connectedDeviceId == null && !advertising) || !applicationPaired) {
      return;
    }
    await _repository.sendMessage(
      jsonEncode({'type': 'debug_wifi_connection_result', 'success': success}),
    );
    _log.info('debug', 'wifi.connection_result_sent', {'success': success});
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
    _runtimeTimer?.cancel();
    _sharingMessages.close();
    _stopPeerMonitoring();
    _reconnectTimer?.cancel();
    _disposed = true;
    if (DebugNotifications.instance.onHotspotResponse ==
        _handleHotspotNotificationAction) {
      DebugNotifications.instance.onHotspotResponse = null;
    }
    _operation++;
    _messageSubscription?.cancel();
    _discoverySubscription?.cancel();
    if (!(_pairingResult?.isCompleted ?? true)) _pairingResult!.complete(false);
    super.dispose();
  }
}
