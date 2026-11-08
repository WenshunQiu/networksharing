import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:networksharing/app/network_sharing_app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('pairing home starts without initializing the Rust demo', (
    tester,
  ) async {
    await tester.pumpWidget(const NetworkSharingApp());
    await tester.pump();
    expect(find.text('连接你的设备'), findsOneWidget);
    expect(find.text('重新生成配对码'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
