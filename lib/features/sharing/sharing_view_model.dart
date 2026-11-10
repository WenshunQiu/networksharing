import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/app_logger.dart';
import '../../data/debug_notifications.dart';
import '../../data/platform_network_control.dart';
import '../../domain/app_settings.dart';
import '../../domain/connectivity.dart';
import '../bluetooth/bluetooth_view_model.dart';
import '../settings/settings_view_model.dart';
import '../status/connectivity_view_model.dart';

enum SharingPhase {
  idle,
  requesting,
  approval,
  preparing,
  joining,
  verifying,
  active,
  failed,
  closed,
}

enum SharingPermission { ask, allow, deny }

typedef NetworkOperation = Future<Map<String, dynamic>> Function(
  String operation, {
  String? ssid,
  String? password,
});
typedef ShareNotification = Future<void> Function(
  String title,
  String body, {
  String? hotspotRequestId,
  bool shareRequestConfirmation,
});

/// Coordinates a single authenticated peer. Debug messages never auto-join Wi-Fi.
/// Native adapters retain control of OS permissions and actual network state.
class SharingViewModel extends ChangeNotifier {
  SharingViewModel(
    this.bluetooth,
    this.connectivity,
    this.settings, {
    NetworkOperation? networkOperation,
    ShareNotification? notification,
    this.tickInterval = const Duration(seconds: 5),
    this.offlineDelay = const Duration(seconds: 15),
    this.requestTimeout = const Duration(minutes: 2),
    DateTime Function()? clock,
  }) : _network = networkOperation ?? PlatformNetworkControl().execute,
       _now = clock ?? DateTime.now,
       _notifyUser = notification ?? DebugNotifications.instance.show {
    _subscription = bluetooth.sharingMessages.listen((message) {
      unawaited(_receive(message));
    });
    bluetooth.addListener(_changed);
    connectivity.addListener(_networkChanged);
    settings.addListener(_settingsChanged);
    DebugNotifications.instance.onShareRequest = requestNetwork;
    DebugNotifications.instance.onSharingApproval = _notificationApproval;
    DebugNotifications.instance.startBackgroundActionListener();
    _timer = Timer.periodic(tickInterval, (_) => unawaited(tick()));
    unawaited(_loadPermissions());
  }

  final BluetoothViewModel bluetooth;
  final ConnectivityViewModel connectivity;
  final SettingsViewModel settings;
  final NetworkOperation _network;
  final ShareNotification _notifyUser;
  final DateTime Function() _now;
  final Duration tickInterval, offlineDelay, requestTimeout;
  final _log = AppLogger.instance;
  late final StreamSubscription<Map<String, dynamic>> _subscription;
  Timer? _timer;
  SharingPhase phase = SharingPhase.idle;
  String status = '已准备好；联网设备可向已配对设备提供热点。';
  String? sessionId;
  bool providing = false;
  bool ownsHotspot = false;
  int? clientCount;
  bool busy = false;
  bool _disposed = false, _ticking = false, _runtimeStarted = false;
  bool _permissionReady = false;
  int _generation = 0;
  DateTime? _deadline,
      _offlineSince,
      _lastPrompt,
      _emptySince,
      _lastClientCheck;
  final Map<String, SharingPermission> _permissions = {};
  final Set<String> _seenRequests = {};
  String? _ownedSsid;
  bool _stopAfterOperation = false;
  bool _stopping = false;
  ConnectivityState? _observedNetworkState;
  bool get connected => bluetooth.applicationPaired && bluetooth.peerOnline;
  bool get pendingApproval => phase == SharingPhase.approval;
  bool get canRequest =>
      connected &&
      _permissionReady &&
      !busy &&
      !_stopping &&
      !inSession &&
      !ownsHotspot;
  bool get inSession => const {
    SharingPhase.requesting,
    SharingPhase.approval,
    SharingPhase.preparing,
    SharingPhase.joining,
    SharingPhase.verifying,
    SharingPhase.active,
  }.contains(phase);
  SharingPermission get permission =>
      _permissions[bluetooth.pairedDeviceId] ?? SharingPermission.ask;

  Future<void> _loadPermissions() async {
    try {
      final preferences = SharedPreferencesAsync();
      _ownedSsid = await preferences.getString(
        'networksharing.ownedHotspotSsid',
      );
      ownsHotspot = _ownedSsid != null;
      final keys = await preferences.getKeys();
      for (final key in keys.where(
        (key) => key.startsWith('networksharing.sharePermission.'),
      )) {
        final value = await preferences.getString(key);
        _permissions[key.substring(
          'networksharing.sharePermission.'.length,
        )] = SharingPermission.values.firstWhere(
          (p) => p.name == value,
          orElse: () => SharingPermission.ask,
        );
      }
    } catch (_) {
      _log.warning('sharing', 'permissions.load_failed');
    }
    _permissionReady = true;
    _changed();
    _settingsChanged();
  }

  Future<void> setPermission(SharingPermission value) async {
    final peer = bluetooth.pairedDeviceId;
    if (peer == null) return;
    try {
      await SharedPreferencesAsync().setString(
        'networksharing.sharePermission.$peer',
        value.name,
      );
      _permissions[peer] = value;
      _log.info('sharing', 'permission.saved', {'permission': value.name});
      if (pendingApproval && value != SharingPermission.ask) {
        await approve(value == SharingPermission.allow);
      }
      _changed();
    } catch (_) {
      _set(phase, '设备授权保存失败，请重试。');
    }
  }

  void _settingsChanged() {
    if (_disposed || settings.loading) return;
    unawaited(
      bluetooth.setBackgroundEnabled(settings.settings.backgroundMonitoring),
    );
    connectivity.setMonitoring(settings.settings.backgroundMonitoring);
    if (!_runtimeStarted &&
        (settings.settings.startMonitoringOnLaunch ||
            defaultTargetPlatform == TargetPlatform.windows)) {
      _runtimeStarted = true;
      unawaited(bluetooth.startRuntime());
    }
    _changed();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _networkChanged() {
    final state = connectivity.snapshot?.state;
    if (!connectivity.checking &&
        state != null &&
        state != _observedNetworkState) {
      _observedNetworkState = state;
      _offlineSince = state == ConnectivityState.offline ? _now() : null;
      if (state == ConnectivityState.online) _lastPrompt = null;
      _log.info('sharing', 'network.changed', {
        'online': state == ConnectivityState.online,
        'phase': phase.name,
        'reminderRearmed': state == ConnectivityState.online,
      });
    }
    _changed();
  }

  void _set(SharingPhase next, String message) {
    if (_disposed) return;
    phase = next;
    status = message;
    _log.info('sharing', 'session.state', {
      'phase': next.name,
      'providing': providing,
      'sessionId': sessionId,
    });
    notifyListeners();
  }

  Future<void> _send(String type, [Map<String, dynamic> payload = const {}]) =>
      bluetooth.sendSharingMessage({
        'type': type,
        'version': 1,
        'sessionId': sessionId,
        ...payload,
      });

  Future<void> tick() async {
    if (_disposed || _ticking || settings.loading) return;
    _ticking = true;
    try {
      final now = _now();
      if (!_permissionReady) return;
      if (_deadline != null && now.isAfter(_deadline!)) {
        await stop(reason: '请求或连接等待超时，请重试。', rearmReminder: false);
        _set(SharingPhase.failed, '请求或连接等待超时，请重试。');
      }
      if (ownsHotspot &&
          !_stopping &&
          !busy &&
          (_lastClientCheck == null ||
              now.difference(_lastClientCheck!) >=
                  const Duration(seconds: 30))) {
        _lastClientCheck = now;
        final current = await _network('getHotspot');
        if (_disposed) return;
        if (current['enabled'] == false ||
            (_ownedSsid != null && current['ssid'] != _ownedSsid)) {
          ownsHotspot = false;
          _ownedSsid = null;
          await SharedPreferencesAsync().remove(
            'networksharing.ownedHotspotSsid',
          );
          clientCount = null;
          _set(SharingPhase.closed, '本机热点已关闭。');
        } else {
          clientCount = (current['clientCount'] as num?)?.toInt();
          // Unknown is not zero. Never close somebody else's hotspot or infer
          // Wi-Fi client absence from a Bluetooth timeout.
          if (clientCount == 0) {
            _emptySince ??= now;
            if (now.difference(_emptySince!) >=
                Duration(minutes: settings.settings.idleTimeoutMinutes)) {
              final confirmed = await _network('getHotspot');
              if (confirmed['clientCount'] == 0) {
                await stop(reason: '热点持续空闲，已自动关闭。');
              }
            }
          } else {
            _emptySince = null;
          }
          _changed();
        }
      }
      final local = connectivity.snapshot;
      if (local?.state != ConnectivityState.offline) {
        _offlineSince = null;
        return;
      }
      _offlineSince ??= now;
      // A completed join must not keep canRequest=false after its network is
      // disconnected outside the app. Retire the old session after debounce.
      if (phase == SharingPhase.active &&
          !providing &&
          !busy &&
          now.difference(_offlineSince!) >= offlineDelay) {
        _log.info('sharing', 'session.network_lost', {'sessionId': sessionId});
        await stop(reason: '共享网络已断开，可重新请求热点。');
      }
      final options = settings.settings;
      if (!options.backgroundMonitoring ||
          !options.notificationsEnabled ||
          options.connectionAutomation == ConnectionAutomation.manualOnly ||
          !canRequest ||
          bluetooth.peerNetworkStatus != '互联网可用' ||
          now.difference(_offlineSince!) < offlineDelay ||
          (_lastPrompt != null &&
              now.difference(_lastPrompt!) < const Duration(minutes: 5))) {
        return;
      }
      _lastPrompt = now;
      _set(SharingPhase.idle, '本机网络不可用，可以请求对方提供热点。');
      await _notifyUser(
        '网络不可用',
        '是否请求已配对设备开启热点？对方确认后将自动连接。',
        shareRequestConfirmation: true,
      );
      _log.info('sharing', 'offline_notification.shown', {
        'sessionId': sessionId,
      });
    } catch (error) {
      _log.warning('sharing', 'monitor.failed', {
        'errorType': error.runtimeType.toString(),
      });
    } finally {
      _ticking = false;
    }
  }

  Future<void> requestNetwork() async {
    if (!canRequest || _disposed) return;
    _generation++;
    sessionId = List.generate(
      16,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    providing = false;
    _deadline = _now().add(requestTimeout);
    _set(SharingPhase.requesting, '已发送热点请求，等待对方允许。');
    try {
      await _send('share_request');
    } catch (_) {
      _deadline = null;
      _set(SharingPhase.failed, '请求发送失败，请等待设备恢复连接后重试。');
    }
  }

  Future<void> _receive(Map<String, dynamic> message) async {
    if (_disposed || !connected || message['version'] != 1) return;
    final id = message['sessionId'];
    if (id is! String || !RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) return;
    try {
      if (message['type'] == 'share_request') {
        if (_seenRequests.contains(id)) return;
        if (_seenRequests.length > 128) _seenRequests.clear();
        _seenRequests.add(id);
        if (inSession ||
            _stopping ||
            busy ||
            ownsHotspot ||
            !_permissionReady ||
            permission == SharingPermission.deny) {
          await bluetooth.sendSharingMessage({
            'type': 'share_response',
            'version': 1,
            'sessionId': id,
            'accepted': false,
          });
          return;
        }
        sessionId = id;
        _generation++;
        providing = true;
        _deadline = _now().add(requestTimeout);
        _set(SharingPhase.approval, '已配对设备请求使用本机热点。');
        if (permission == SharingPermission.allow) {
          await approve(true);
        } else if (settings.settings.notificationsEnabled) {
          try {
            await _notifyUser(
              '热点共享请求',
              '${bluetooth.pairedDeviceName ?? '已配对设备'} 请求本机提供网络。',
              hotspotRequestId: id,
            );
          } catch (_) {
            _set(SharingPhase.approval, '通知不可用，请在设备状态页确认热点请求。');
          }
        }
        return;
      }
      if (id != sessionId) return;
      if (message['type'] == 'share_cancel') {
        await stop(send: false, reason: '对方结束了共享。');
        return;
      }
      if (!inSession) return;
      switch (message['type']) {
        case 'share_response':
          if (providing || phase != SharingPhase.requesting) return;
          if (message['accepted'] == true) {
            _set(SharingPhase.requesting, '对方已允许，正在准备热点。');
          } else {
            _deadline = null;
            _set(SharingPhase.closed, '对方拒绝、正忙或禁止了共享请求。');
          }
        case 'share_credentials':
          if (providing || phase != SharingPhase.requesting) return;
          final ssid = message['ssid'], password = message['password'];
          if (ssid is! String || password is! String || ssid.isEmpty) return;
          await _join(id, ssid, password);
        case 'share_result':
          if (!providing || phase != SharingPhase.preparing) return;
          _deadline = null;
          _set(
            message['online'] == true
                ? SharingPhase.active
                : SharingPhase.failed,
            message['online'] == true
                ? '对方已连接，正在共享网络。'
                : '对方未能验证共享网络；可重试或停止热点。',
          );
        case 'share_cancel':
          await stop(send: false, reason: '对方结束了共享。');
        case 'share_error':
          await stop(send: false, reason: '对方未能完成热点操作。');
          _set(SharingPhase.failed, '对方未能完成热点操作，请检查对方日志。');
      }
    } catch (error) {
      _log.error('sharing', 'message.failed', {
        'errorType': error.runtimeType.toString(),
      });
      if (id == sessionId) {
        _deadline = null;
        _set(SharingPhase.failed, '共享流程失败，请重试或停止本机热点。');
      }
    }
  }

  Future<bool> _notificationApproval(String id, bool accepted) async {
    // All normal share IDs are 32 hex digits; Debug request IDs remain separate.
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) return false;
    if (id == sessionId && pendingApproval) await approve(accepted);
    return true;
  }

  Future<void> approve(bool accepted) async {
    if (!pendingApproval || !connected || busy || _disposed) return;
    if (_deadline == null || _now().isAfter(_deadline!)) return;
    final generation = _generation;
    final id = sessionId;
    // Consume the approval before asynchronous work; duplicate taps cannot start twice.
    _set(
      accepted ? SharingPhase.preparing : SharingPhase.closed,
      accepted ? '正在检查网络并开启本机热点…' : '已拒绝此次共享。',
    );
    if (!accepted) {
      _deadline = null;
      await _send('share_response', {'accepted': false});
      return;
    }
    busy = true;
    try {
      await _send('share_response', {'accepted': true});
      await connectivity.refresh();
      if (_disposed || generation != _generation) return;
      if (connectivity.snapshot?.state != ConnectivityState.online) {
        throw StateError('本机当前无互联网，无法提供网络');
      }
      final previous = await _network('getHotspot');
      if (_disposed || generation != _generation) return;
      final alreadyEnabled = previous['enabled'] == true;
      final result = alreadyEnabled ? previous : await _network('startHotspot');
      if (!alreadyEnabled && result['enabled'] == true) {
        ownsHotspot = true;
        _ownedSsid = result['ssid'] as String?;
        if (_ownedSsid != null) {
          await SharedPreferencesAsync().setString(
            'networksharing.ownedHotspotSsid',
            _ownedSsid!,
          );
        }
      }
      if (_disposed || generation != _generation) {
        if (ownsHotspot) {
          await _closeOwnedHotspot();
        }
        return;
      }
      final ssid = result['ssid'], password = result['password'];
      if (result['enabled'] != true ||
          ssid is! String ||
          ssid.isEmpty ||
          password is! String) {
        throw StateError('无法获取已启用热点的接入信息');
      }
      _emptySince = _now();
      _lastClientCheck = null;
      _set(SharingPhase.preparing, '热点已准备好，等待对方连接。');
      await _send('share_credentials', {'ssid': ssid, 'password': password});
      _log.info('sharing', 'credentials.sent', {'ownsHotspot': ownsHotspot});
    } catch (error) {
      _deadline = null;
      if (generation == _generation && !_disposed) {
        try {
          await _send('share_error');
        } catch (_) {}
        _set(SharingPhase.failed, '开启共享失败：$error');
      }
    } finally {
      busy = false;
      if (_stopAfterOperation && !_disposed) {
        _stopAfterOperation = false;
        await stop(send: false);
      }
      if (sessionId == id) _changed();
    }
  }

  Future<void> _join(String id, String ssid, String password) async {
    final generation = _generation;
    busy = true;
    _set(SharingPhase.joining, '正在连接对方热点；系统要求时请确认 Wi-Fi 授权。');
    try {
      await _network('connectWifi', ssid: ssid, password: password);
      if (_disposed || generation != _generation) return;
      _set(SharingPhase.verifying, 'Wi-Fi 已关联，正在验证互联网…');
      var online = false;
      for (var attempt = 0; attempt < 3; attempt++) {
        await connectivity.refresh();
        if (_disposed || generation != _generation) return;
        online = connectivity.snapshot?.state == ConnectivityState.online;
        if (online) break;
        if (attempt < 2) await Future<void>.delayed(const Duration(seconds: 2));
      }
      _deadline = null;
      await _send('share_result', {'online': online});
      _set(
        online ? SharingPhase.active : SharingPhase.failed,
        online ? '共享网络已连接，互联网检测通过。' : 'Wi-Fi 已连接，但互联网验证未通过。',
      );
    } catch (error) {
      _deadline = null;
      if (!_disposed && generation == _generation) {
        try {
          await _send('share_result', {'online': false});
        } catch (_) {}
        _set(SharingPhase.failed, '连接共享网络失败：$error');
      }
    } finally {
      busy = false;
      if (_stopAfterOperation && !_disposed) {
        _stopAfterOperation = false;
        await stop(send: false);
      }
      _changed();
    }
  }

  Future<void> stop({
    bool send = true,
    String reason = '已结束共享。',
    bool rearmReminder = true,
  }) async {
    if (_disposed || _stopping) return;
    _stopping = true;
    try {
      _generation++;
      _deadline = null;
      // Cooldown belongs to reminders in the same offline episode, not to
      // stopping a successful session. A fresh disconnect can prompt again.
      if (rearmReminder) {
        _lastPrompt = null;
        _log.info('sharing', 'offline_notification.rearmed', {
          'sessionId': sessionId,
        });
      }
      if (busy) _stopAfterOperation = true;
      if (send && sessionId != null && connected) {
        try {
          await _send('share_cancel');
        } catch (_) {}
      }
      if (ownsHotspot && !busy) {
        try {
          await _closeOwnedHotspot();
        } catch (_) {
          _set(SharingPhase.failed, '关闭本机热点失败，请再次点击停止共享。');
          return;
        }
      }
      _set(SharingPhase.closed, reason);
    } finally {
      _stopping = false;
      _changed();
    }
  }

  Future<void> _closeOwnedHotspot() async {
    final current = await _network('getHotspot');
    if (current['enabled'] == true &&
        (_ownedSsid == null || current['ssid'] == _ownedSsid)) {
      final stopped = await _network('stopHotspot');
      if (stopped['enabled'] == true) throw StateError('系统尚未确认热点关闭');
    }
    ownsHotspot = false;
    _ownedSsid = null;
    clientCount = null;
    await SharedPreferencesAsync().remove('networksharing.ownedHotspotSsid');
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    _subscription.cancel();
    bluetooth.removeListener(_changed);
    connectivity.removeListener(_networkChanged);
    settings.removeListener(_settingsChanged);
    DebugNotifications.instance.onShareRequest = null;
    DebugNotifications.instance.onSharingApproval = null;
    DebugNotifications.instance.stopBackgroundActionListener();
    super.dispose();
  }
}
