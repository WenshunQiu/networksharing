import 'dart:convert';

enum PairingMessageType { hello, challenge, proof, accepted, rejected }

class PairingEnvelope {
  const PairingEnvelope({
    required this.messageId,
    required this.sessionId,
    required this.type,
    required this.sentAt,
    required this.sequence,
    this.payload = const {},
    this.protocolVersion = currentVersion,
  });

  static const currentVersion = 1;
  final int protocolVersion;
  final String messageId;
  final String sessionId;
  final PairingMessageType type;
  final DateTime sentAt;
  final int sequence;
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() => {
    'version': protocolVersion,
    'messageId': messageId,
    'sessionId': sessionId,
    'type': type.name,
    'sentAt': sentAt.toUtc().toIso8601String(),
    'sequence': sequence,
    'payload': payload,
  };

  String encode() => jsonEncode(toJson());

  static PairingEnvelope decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Message envelope must be an object.');
    }
    final version = decoded['version'];
    if (version != currentVersion) {
      throw FormatException('Unsupported pairing protocol version: $version');
    }
    final typeName = decoded['type'];
    final type = PairingMessageType.values.where(
      (item) => item.name == typeName,
    );
    final payload = decoded['payload'];
    if (type.isEmpty || payload is! Map<String, dynamic>) {
      throw const FormatException('Invalid pairing message type or payload.');
    }
    final messageId = decoded['messageId'];
    final sessionId = decoded['sessionId'];
    final timestamp = decoded['sentAt'];
    final sequence = decoded['sequence'];
    if (messageId is! String ||
        messageId.isEmpty ||
        sessionId is! String ||
        sessionId.isEmpty ||
        timestamp is! String ||
        sequence is! int ||
        sequence < 0) {
      throw const FormatException('Invalid pairing envelope fields.');
    }
    return PairingEnvelope(
      messageId: messageId,
      sessionId: sessionId,
      type: type.first,
      sentAt: DateTime.parse(timestamp).toUtc(),
      sequence: sequence,
      payload: payload,
      protocolVersion: version as int,
    );
  }
}

class PairingSequenceGuard {
  String? _sessionId;
  int _lastSequence = -1;
  final Set<String> _seenIds = {};

  bool accept(PairingEnvelope message) {
    if (_sessionId != message.sessionId) {
      _sessionId = message.sessionId;
      _lastSequence = -1;
      _seenIds.clear();
    }
    if (_seenIds.contains(message.messageId) ||
        message.sequence <= _lastSequence) {
      return false;
    }
    _seenIds.add(message.messageId);
    _lastSequence = message.sequence;
    return true;
  }
}
