import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:networksharing/data/debug_notifications.dart';
import 'package:networksharing/domain/app_settings.dart';
import 'package:networksharing/domain/connectivity.dart';
import 'package:networksharing/features/bluetooth/bluetooth_view_model.dart';
import 'package:networksharing/features/settings/settings_repository.dart';
import 'package:networksharing/features/settings/settings_view_model.dart';
import 'package:networksharing/features/sharing/sharing_view_model.dart';
import 'package:networksharing/features/status/connectivity_view_model.dart';
import 'package:networksharing/features/status/device_status_page.dart';

import 'bluetooth_test.dart' show FakeBluetoothRepository;

class Link extends BluetoothViewModel {
  Link() : super(FakeBluetoothRepository(), autoRecoverOnRestore: false);
  final incoming = StreamController<Map<String, dynamic>>.broadcast();
  final sent = <Map<String, dynamic>>[];
  int runtimeStarts = 0;
  @override
  Stream<Map<String, dynamic>> get sharingMessages => incoming.stream;
  @override
  Future<void> sendSharingMessage(Map<String, dynamic> message) async {
    sent.add(message);
  }

  @override
  Future<void> startRuntime() async {
    runtimeStarts++;
  }

  @override
  Future<void> setBackgroundEnabled(bool enabled) async {}
  @override
  void dispose() {
    incoming.close();
    super.dispose();
  }
}

class Network implements ConnectivityRepository {
  bool online = true;
  @override
  Future<ConnectivitySnapshot> check() async => ConnectivitySnapshot(
    state: online ? ConnectivityState.online : ConnectivityState.offline,
    checkedAt: DateTime.now(),
  );
}

class Preferences implements SettingsRepository {
  AppSettings value = const AppSettings();
  @override
  Future<AppSettings> load() async => value;
  @override
  Future<void> save(AppSettings settings) async {
    value = settings;
  }
}

Future<void> flush() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Link link;
  late Network internet;
  late ConnectivityViewModel connectivity;
  late SettingsViewModel settings;
  late SharingViewModel sharing;
  late DateTime clock;
  late List<String> operations;
  late List<String> prompts;
  bool enabled = false;
  int? clients = 0;
  Completer<Map<String, dynamic>>? pendingStart;
  const id = '0123456789abcdef0123456789abcdef';

  Future<Map<String, dynamic>> operate(
    String operation, {
    String? ssid,
    String? password,
  }) async {
    operations.add(operation);
    if (operation == 'startHotspot') {
      if (pendingStart != null) return pendingStart!.future;
      enabled = true;
    }
    if (operation == 'stopHotspot') enabled = false;
    if (operation == 'connectWifi') internet.online = true;
    return {
      'success': true,
      'enabled': enabled,
      'ssid': 'SharedWiFi',
      'password': 'test-password',
      'clientCount': ?clients,
    };
  }

  void receive(String type, [Map<String, dynamic> data = const {}]) {
    link.incoming.add({'type': type, 'version': 1, 'sessionId': id, ...data});
  }

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    enabled = false;
    clients = 0;
    pendingStart = null;
    operations = [];
    prompts = [];
    clock = DateTime(2026, 11, 10);
    link = Link();
    internet = Network();
    connectivity = ConnectivityViewModel(internet);
    settings = SettingsViewModel(Preferences());
    sharing = SharingViewModel(
      link,
      connectivity,
      settings,
      tickInterval: const Duration(days: 1),
      clock: () => clock,
      networkOperation: operate,
      notification:
          (
            title,
            body, {
            hotspotRequestId,
            shareRequestConfirmation = false,
          }) async {
            prompts.add(hotspotRequestId ?? 'offline');
          },
    );
    await flush();
    link.applicationPaired = true;
    link.peerOnline = true;
    link.pairedDeviceId = 'peer-one';
    link.peerNetworkStatus = '互联网可用';
  });

  tearDown(() async {
    sharing.dispose();
    settings.dispose();
    connectivity.dispose();
    link.dispose();
    await flush();
  });

  testWidgets('paired device permission dialog saves automatic denial', (
    tester,
  ) async {
    tester.view.physicalSize = const ui.Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ui.FluentApp(
        home: ui.ScaffoldPage(
          content: DeviceStatusPage(
            viewModel: connectivity,
            bluetoothViewModel: link,
            sharingViewModel: sharing,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('管理权限'));
    await tester.pumpAndSettle();
    expect(find.text('每次询问'), findsOneWidget);
    expect(find.text('自动同意'), findsOneWidget);
    await tester.tap(find.text('自动拒绝'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(sharing.permission, SharingPermission.deny);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const ui.SizedBox());
  });

  test(
    'persistent allow grants subsequent request without prompting',
    () async {
      await sharing.setPermission(SharingPermission.allow);
      sharing.dispose();
      sharing = SharingViewModel(
        link,
        connectivity,
        settings,
        tickInterval: const Duration(days: 1),
        clock: () => clock,
        networkOperation: operate,
        notification:
            (
              title,
              body, {
              hotspotRequestId,
              shareRequestConfirmation = false,
            }) async {
              prompts.add(hotspotRequestId ?? 'offline');
            },
      );
      await flush();
      expect(sharing.permission, SharingPermission.allow);
      receive('share_request');
      await flush();
      expect(prompts, isEmpty);
      expect(operations.where((p) => p == 'startHotspot').length, 1);
      expect(link.sent.last['type'], 'share_credentials');
    },
  );

  test('startup activates recovery without visiting the pairing page', () {
    expect(link.runtimeStarts, 1);
  });

  test(
    'offline prompt is debounced and respects notification preference',
    () async {
      internet.online = false;
      await connectivity.refresh();
      await sharing.tick();
      expect(prompts, isEmpty);
      clock = clock.add(const Duration(seconds: 20));
      await sharing.tick();
      await sharing.tick();
      expect(prompts, ['offline']);
      clock = clock.add(const Duration(minutes: 6));
      await settings.update(
        settings.settings.copyWith(notificationsEnabled: false),
      );
      await sharing.tick();
      expect(prompts, ['offline']);
    },
  );

  test('provider notification approval starts once, sends credentials and closes after idle', () async {
    receive('share_request');
    await flush();
    expect(sharing.phase, SharingPhase.approval);
    expect(prompts, [id]);
    await DebugNotifications.instance.onSharingApproval!(id, true);
    await DebugNotifications.instance.onSharingApproval!(id, true);
    expect(operations.where((p) => p == 'startHotspot').length, 1);
    expect(link.sent.last['type'], 'share_credentials');
    expect(sharing.ownsHotspot, isTrue);
    receive('share_result', {'online': true});
    await flush();
    expect(sharing.phase, SharingPhase.active);
    await sharing.tick();
    clock = clock.add(const Duration(minutes: 11));
    await sharing.tick();
    expect(enabled, isFalse);
    expect(sharing.phase, SharingPhase.closed);
  });

  test(
    'unrelated credentials are ignored; matching credentials join and verify',
    () async {
      internet.online = false;
      await connectivity.refresh();
      await sharing.requestNetwork();
      receive('share_credentials', {'ssid': 'Other', 'password': 'test-pass'});
      await flush();
      expect(operations, isEmpty);
      link.incoming.add({
        'type': 'share_credentials',
        'version': 1,
        'sessionId': sharing.sessionId,
        'ssid': 'SharedWiFi',
        'password': 'test-password',
      });
      await flush();
      expect(operations, ['connectWifi']);
      expect(sharing.phase, SharingPhase.active);
      expect(link.sent.last['type'], 'share_result');
      expect(link.sent.last['online'], isTrue);
    },
  );

  test('pre-existing hotspot is reused and never owned or stopped', () async {
    enabled = true;
    receive('share_request');
    await flush();
    await sharing.approve(true);
    expect(sharing.ownsHotspot, isFalse);
    expect(operations, ['getHotspot']);
    await sharing.stop();
    expect(enabled, isTrue);
    expect(operations, ['getHotspot']);
  });

  test('unknown client count never triggers idle close', () async {
    clients = null;
    receive('share_request');
    await flush();
    await sharing.approve(true);
    receive('share_result', {'online': true});
    await flush();
    clock = clock.add(const Duration(hours: 1));
    await sharing.tick();
    expect(enabled, isTrue);
    expect(operations, isNot(contains('stopHotspot')));
  });

  test('cancel while starting cleans up owned hotspot and does not send credentials', () async {
    pendingStart = Completer<Map<String, dynamic>>();
    receive('share_request');
    await flush();
    final approval = sharing.approve(true);
    await flush();
    receive('share_cancel');
    await flush();
    enabled = true;
    pendingStart!.complete({
      'success': true,
      'enabled': true,
      'ssid': 'SharedWiFi',
      'password': 'test-password',
    });
    await approval;
    expect(enabled, isFalse);
    expect(link.sent.where((m) => m['type'] == 'share_credentials'), isEmpty);
    expect(sharing.phase, SharingPhase.closed);
  });

  test(
    'timeout closes pending request and stale approval cannot start hotspot',
    () async {
      receive('share_request');
      await flush();
      clock = clock.add(const Duration(minutes: 3));
      await sharing.tick();
      await DebugNotifications.instance.onSharingApproval!(id, true);
      expect(sharing.phase, SharingPhase.failed);
      expect(operations, isEmpty);
    },
  );

  test(
    'device deny permission persists and rejects without notification',
    () async {
      await sharing.setPermission(SharingPermission.deny);
      expect(
        await SharedPreferencesAsync().getString(
          'networksharing.sharePermission.peer-one',
        ),
        'deny',
      );
      receive('share_request');
      await flush();
      expect(prompts, isEmpty);
      expect(link.sent.last['accepted'], false);
      expect(operations, isEmpty);
    },
  );

  test('Android background entrypoint delivers choice to live session without UI launch', () async {
    receive('share_request');
    await flush();
    networkSharingNotificationBackgroundAction(
      const NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
        actionId: 'hotspot:accept:0123456789abcdef0123456789abcdef',
      ),
    );
    await flush();
    await DebugNotifications.instance.drainBackgroundActions();
    expect(operations.where((p) => p == 'startHotspot').length, 1);
    await DebugNotifications.instance.drainBackgroundActions();
    expect(operations.where((p) => p == 'startHotspot').length, 1);
  });
}
