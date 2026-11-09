import 'package:fluent_ui/fluent_ui.dart';

import 'src/rust/frb_generated.dart';
import 'data/app_logger.dart';
import 'data/debug_notifications.dart';

import 'app/network_sharing_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppLogger.instance.info('app', 'startup');
  await RustLib.init();
  try {
    await DebugNotifications.instance.initialize();
  } catch (error) {
    AppLogger.instance.warning('notification', 'initialize.failed', {
      'errorType': error.runtimeType.toString(),
    });
  }
  runApp(const NetworkSharingApp());
}
