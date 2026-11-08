import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:networksharing/domain/pairing_protocol.dart';

void main() {
  PairingEnvelope message(
    int sequence, {
    String? id,
    String session = 'session-a',
  }) => PairingEnvelope(
    messageId: id ?? 'message-$sequence',
    sessionId: session,
    type: PairingMessageType.hello,
    sentAt: DateTime.utc(2026, 11, 8),
    sequence: sequence,
    payload: const {
      'capabilities': ['pairing'],
    },
  );

  test('round trips versioned messages', () {
    final original = message(1);
    final decoded = PairingEnvelope.decode(original.encode());
    expect(decoded.protocolVersion, 1);
    expect(decoded.sessionId, original.sessionId);
    expect(decoded.type, PairingMessageType.hello);
    expect(decoded.payload, original.payload);
  });

  test('rejects unknown protocol versions and message types', () {
    final futureVersion = message(1).toJson()..['version'] = 9;
    expect(
      () => PairingEnvelope.decode(jsonEncode(futureVersion)),
      throwsFormatException,
    );
    final unknownType = message(1).toJson()..['type'] = 'future';
    expect(
      () => PairingEnvelope.decode(jsonEncode(unknownType)),
      throwsFormatException,
    );
  });

  test('sequence guard rejects duplicates and stale messages per session', () {
    final guard = PairingSequenceGuard();
    expect(guard.accept(message(1)), isTrue);
    expect(guard.accept(message(1)), isFalse);
    expect(guard.accept(message(0)), isFalse);
    expect(guard.accept(message(0, session: 'session-b')), isTrue);
  });
}
