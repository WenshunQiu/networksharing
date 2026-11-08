abstract interface class PairingRepository {
  Future<PairingCodeSession> createSession();
  Future<PairingResult> pair(String code);
}

class PairingCodeSession {
  const PairingCodeSession({
    required this.sessionId,
    required this.code,
    required this.expiresAt,
  });
  final String sessionId;
  final String code;
  final DateTime expiresAt;
}

class PairingResult {
  const PairingResult({required this.success, required this.message});

  final bool success;
  final String message;
}

/// Placeholder until platform Bluetooth discovery and authenticated transport
/// are implemented. It deliberately never reports a successful pairing.
class UnavailablePairingRepository implements PairingRepository {
  @override
  Future<PairingCodeSession> createSession() async {
    throw StateError('Rust pairing bridge is unavailable.');
  }

  @override
  Future<PairingResult> pair(String code) async {
    return const PairingResult(success: false, message: '蓝牙配对功能尚未接入，请稍后再试。');
  }
}
