import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'app_logger.dart';

class DebugNotifications {
  DebugNotifications._();
  static final instance = DebugNotifications._();
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _initialization;
  Future<void> Function(String requestId, bool accepted)? _onHotspotResponse;
  (String, bool)? _pendingAction;

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
        onDidReceiveNotificationResponse: (response) {
          final parts = (response.actionId ?? '').split(':');
          if (parts.length == 3 && parts.first == 'hotspot') {
            unawaited(_respond(parts[2], parts[1] == 'accept'));
          }
        },
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

  Future<void> _respond(String id, bool accepted) async {
    try {
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
    final parts = action.split(':');
    if (parts.length == 3 && parts.first == 'hotspot') {
      unawaited(_respond(parts[2], parts[1] == 'accept'));
    }
  }

  Future<void> show(
    String title,
    String body, {
    String? hotspotRequestId,
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
          'networksharing_debug',
          'NetworkSharing Debug',
          importance: Importance.max,
          priority: Priority.high,
          actions: [
            if (hotspotRequestId != null) ...[
              AndroidNotificationAction(
                'hotspot:accept:$hotspotRequestId',
                '允许开启',
                showsUserInterface: true,
              ),
              AndroidNotificationAction(
                'hotspot:reject:$hotspotRequestId',
                '拒绝',
                showsUserInterface: true,
              ),
            ],
          ],
        ),
        windows: WindowsNotificationDetails(
          actions: [
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
      'confirmation': hotspotRequestId != null,
    });
  }
}
