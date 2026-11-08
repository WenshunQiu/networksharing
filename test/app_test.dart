import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:networksharing/app/network_sharing_app.dart';
import 'package:networksharing/features/pairing/pairing_repository.dart';

void main() {
  for (final width in [390.0, 1200.0]) {
    testWidgets('pairing page adapts at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        NetworkSharingApp(pairingRepository: TestPairingRepository()),
      );
      await tester.pump();
      expect(find.text('连接你的设备'), findsOneWidget);
      expect(find.text('重新生成配对码'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}

class TestPairingRepository implements PairingRepository {
  @override
  Future<PairingCodeSession> createSession() async => PairingCodeSession(
    sessionId: 'test-session',
    code: 'ABC234',
    expiresAt: DateTime.now().add(const Duration(minutes: 5)),
  );
  @override
  Future<PairingResult> pair(String code) async => const PairingResult(
    success: false,
    message: 'Bluetooth transport unavailable.',
  );
}
