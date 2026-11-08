import '../features/pairing/pairing_repository.dart';
import '../src/rust/api/pairing.dart' as rust_pairing;

class RustPairingRepository implements PairingRepository {
  @override
  Future<PairingCodeSession> createSession() async {
    final session = await rust_pairing.createPairingSession();
    return PairingCodeSession(
      sessionId: session.sessionId,
      code: session.pairingCode,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        session.expiresAtUnixMs.toInt(),
        isUtc: true,
      ).toLocal(),
    );
  }

  @override
  Future<PairingResult> pair(String code) async =>
      const PairingResult(success: false, message: '蓝牙发现、认证与传输尚未接入。');
}
