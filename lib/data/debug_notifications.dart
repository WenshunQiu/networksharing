import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_logger.dart';

class DebugNotifications {
  DebugNotifications._();
  static final instance = DebugNotifications._();
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _initialization;
  Future<void> Function(String requestId, bool accepted)? _onHotspotResponse;
  Future<void> Function()? _onShareRequest;
  Future<bool> Function(String requestId, bool accepted)? onSharingApproval;
  (String, bool)? _pendingAction;
  bool _pendingShareRequest = false;
  final Set<String> _pendingActions = {};
  Timer? _actionPoller;
  bool _draining = false;

  void startBackgroundActionListener() {
    _actionPoller ??= Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(drainBackgroundActions());
    });
    unawaited(drainBackgroundActions());
  }

  void stopBackgroundActionListener() {
    _actionPoller?.cancel();
    _actionPoller = null;
  }

  Future<void> drainBackgroundActions() async {
    if (_draining) return;
    _draining = true;
    try {
      final preferences = SharedPreferencesAsync();
      final keys = await preferences.getKeys();
      for (final key in keys.where(
        (key) => key.startsWith(notificationActionPrefix),
      )) {
        final action = await preferences.getString(key);
        await preferences.remove(key);
        final created = int.tryParse(
          key.substring(notificationActionPrefix.length),
        );
        if (created == null ||
            DateTime.now().microsecondsSinceEpoch - created >
                const Duration(minutes: 2).inMicroseconds) {
          continue;
        }
        final actionId = '$created:$action';
        if (!_pendingActions.add(actionId)) continue;
        AppLogger.instance.info('notification', 'background_action.received');
        await _dispatchAction(action);
        _pendingActions.remove(actionId);
      }
    } catch (error) {
      AppLogger.instance.warning('notification', 'background_action.failed', {
        'errorType': error.runtimeType.toString(),
      });
    } finally {
      _draining = false;
    }
  }

  set onShareRequest(Future<void> Function()? callback) {
    _onShareRequest = callback;
    if (callback != null && _pendingShareRequest) {
      _pendingShareRequest = false;
      unawaited(callback());
    }
  }

  Future<void> Function(String requestId, bool accepted)?
  get onHotspotResponse => _onHotspotResponse;
  set onHotspotResponse(
    Future<void> Function(String requestId, bool accepted)? callback,
  ) {
    _onHotspotResponse = callback;
    final pending = _pendingAction;
    if (pending != null && callback != null) {
      _pendingAction = null;
      unawaited(_respond(pending.$1, pending.$2));
    }
  }

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const windows = WindowsInitializationSettings(
        appName: 'NetworkSharing',
        appUserModelId: 'com.example.networksharing',
        guid: 'A91F27AD-912D-4559-9AF2-7367C1A933A0',
      );
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: android,
          windows: windows,
        ),
        onDidReceiveNotificationResponse: (response) =>
            unawaited(_dispatchAction(response.actionId)),
        onDidReceiveBackgroundNotificationResponse:
            networkSharingNotificationBackgroundAction,
      );
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final action = launch?.notificationResponse?.actionId;
      if (launch?.didNotificationLaunchApp == true && action != null) {
        _queueAction(action);
      }
    } catch (_) {
      _initialization = null;
      rethrow;
    }
  }

  Future<void> _dispatchAction(String? action) async {
    if (action == null) return;
    final parts = action.split(':');
    if (parts.length == 3 && parts.first == 'hotspot') {
      await _respond(parts[2], parts[1] == 'accept');
    } else if (action == 'share:request') {
      final callback = _onShareRequest;
      if (callback == null) {
        _pendingShareRequest = true;
      } else {
        await callback();
      }
    }
  }

  Future<void> _respond(String id, bool accepted) async {
    try {
      if (await onSharingApproval?.call(id, accepted) == true) return;
      final callback = _onHotspotResponse;
      if (callback == null) {
        _pendingAction = (id, accepted);
        return;
      }
      await callback(id, accepted);
    } catch (error) {
      AppLogger.instance.error('notification', 'action.failed', {
        'errorType': error.runtimeType.toString(),
      });
    }
  }

  void _queueAction(String action) {
    unawaited(_dispatchAction(action));
  }

  Future<void> show(
    String title,
    String body, {
    String? hotspotRequestId,
    bool shareRequestConfirmation = false,
  }) async {
    await initialize();
    if (defaultTargetPlatform == TargetPlatform.android) {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      if (granted == false) throw StateError('通知权限未允许');
    }
    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch.remainder(1 << 30),
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'networksharing_sharing',
          'NetworkSharing 网络共享',
          importance: Importance.max,
          priority: Priority.high,
          actions: [
            if (shareRequestConfirmation)
              const AndroidNotificationAction(
                'share:request',
                '请求对方热点',
                showsUserInterface: false,
              ),
            if (hotspotRequestId != null) ...[
              AndroidNotificationAction(
                'hotspot:accept:$hotspotRequestId',
                '允许开启',
                showsUserInterface: false,
              ),
              AndroidNotificationAction(
                'hotspot:reject:$hotspotRequestId',
                '拒绝',
                showsUserInterface: false,
              ),
            ],
          ],
        ),
        windows: WindowsNotificationDetails(
          actions: [
            if (shareRequestConfirmation)
              const WindowsAction(
                content: '请求对方热点',
                arguments: 'share:request',
              ),
            if (hotspotRequestId != null) ...[
              WindowsAction(
                content: '允许开启',
                arguments: 'hotspot:accept:$hotspotRequestId',
              ),
              WindowsAction(
                content: '拒绝',
                arguments: 'hotspot:reject:$hotspotRequestId',
              ),
            ],
          ],
        ),
      ),
    );
    AppLogger.instance.info('notification', 'shown', {
      'hotspotConfirmation': hotspotRequestId != null,
      'shareRequestConfirmation': shareRequestConfirmation,
    });
  }
}

/// Notification action entrypoint used when Android starts a background isolate.
/// Persist the choice so the existing BLE engine can process it without opening
/// the application Activity or creating a competing BLE connection.
@pragma('vm:entry-point')
void networkSharingNotificationBackgroundAction(
  NotificationResponse response,
) async {
  final action = response.actionId;
  if (action == null) return;
  await SharedPreferencesAsync().setString(
    '$notificationActionPrefix${DateTime.now().microsecondsSinceEpoch}',
    action,
  );
}

const notificationActionPrefix = 'networksharing.notificationAction.';
