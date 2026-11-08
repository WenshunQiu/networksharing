import 'dart:convert';
import 'dart:typed_data';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';

/// UUIDs reserved for the Network Sharing control channel.
const controlServiceUuid = '77a10001-7a4b-4d31-9b22-7b8e12a45001';
const controlWriteUuid = '77a10002-7a4b-4d31-9b22-7b8e12a45001';
const controlNotifyUuid = '77a10003-7a4b-4d31-9b22-7b8e12a45001';
const cccDescriptorUuid = '00002902-0000-1000-8000-00805f9b34fb';

const maxControlMessageBytes = 65535;
const _maxConcurrentMessages = 8;
const _fragmentHeaderBytes = 6;

/// Splits a UTF-8 message into frames: message ID, total length, offset, bytes.
List<Uint8List> encodeControlFrames(String message, int maxFrameBytes) {
  final body = Uint8List.fromList(utf8.encode(message));
  if (body.isEmpty || body.length > maxControlMessageBytes) {
    throw const FormatException('invalid_control_message_size');
  }
  if (maxFrameBytes <= _fragmentHeaderBytes) {
    throw const FormatException('control_frame_size_too_small');
  }
  final messageId = _nextMessageId++ & 0xffff;
  final result = <Uint8List>[];
  final payloadSize = maxFrameBytes - _fragmentHeaderBytes;
  for (var offset = 0; offset < body.length;) {
    final end = (offset + payloadSize).clamp(0, body.length);
    result.add(
      Uint8List.fromList([
        messageId >> 8,
        messageId & 0xff,
        body.length >> 8,
        body.length & 0xff,
        offset >> 8,
        offset & 0xff,
        ...body.sublist(offset, end),
      ]),
    );
    offset = end;
  }
  return result;
}

var _nextMessageId = 0;

/// Decodes complete frames while retaining an incomplete trailing frame.
class ControlFrameDecoder {
  final Map<int, _PartialMessage> _messages = {};

  void reset() => _messages.clear();

  String? add(List<int> frame) {
    if (frame.length <= _fragmentHeaderBytes) {
      throw const FormatException('empty_control_fragment');
    }
    final id = (frame[0] << 8) | frame[1];
    final total = (frame[2] << 8) | frame[3];
    final offset = (frame[4] << 8) | frame[5];
    final chunk = frame.sublist(_fragmentHeaderBytes);
    if (total == 0 ||
        total > maxControlMessageBytes ||
        offset + chunk.length > total) {
      throw const FormatException('invalid_control_fragment');
    }
    var partial = _messages[id];
    if (partial == null) {
      if (_messages.length >= _maxConcurrentMessages) {
        _messages.remove(_messages.keys.first);
      }
      partial = _PartialMessage(total);
      _messages[id] = partial;
    }
    if (partial.bytes.length != total ||
        List<int>.generate(
          chunk.length,
          (index) => offset + index,
        ).any(partial.received.contains)) {
      _messages.remove(id);
      throw const FormatException('conflicting_control_fragment');
    }
    partial.bytes.setRange(offset, offset + chunk.length, chunk);
    for (var index = offset; index < offset + chunk.length; index++) {
      partial.received.add(index);
    }
    partial.receivedBytes += chunk.length;
    if (partial.receivedBytes != total) return null;
    _messages.remove(id);
    return utf8.decode(partial.bytes, allowMalformed: false);
  }
}

class _PartialMessage {
  _PartialMessage(int length) : bytes = Uint8List(length);
  final Uint8List bytes;
  final Set<int> received = {};
  int receivedBytes = 0;
}

final controlService = GATTService(
  uuid: UUID.fromString(controlServiceUuid),
  isPrimary: true,
  includedServices: const [],
  characteristics: [
    GATTCharacteristic.mutable(
      uuid: UUID.fromString(controlWriteUuid),
      properties: [GATTCharacteristicProperty.write],
      permissions: [GATTCharacteristicPermission.write],
      descriptors: const [],
    ),
    GATTCharacteristic.mutable(
      uuid: UUID.fromString(controlNotifyUuid),
      properties: [GATTCharacteristicProperty.notify],
      permissions: const [],
      descriptors: [
        GATTDescriptor.mutable(
          uuid: UUID.fromString(cccDescriptorUuid),
          permissions: [
            GATTCharacteristicPermission.read,
            GATTCharacteristicPermission.write,
          ],
        ),
      ],
    ),
  ],
);
