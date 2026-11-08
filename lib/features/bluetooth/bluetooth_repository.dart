enum BluetoothState { ready, poweredOff, unavailable, permissionDenied, failed }

class BluetoothDevice {
  const BluetoothDevice({required this.id, required this.name});
  final String id;
  final String name;
}

class BluetoothSnapshot {
  const BluetoothSnapshot({required this.state, this.devices = const []});
  final BluetoothState state;
  final List<BluetoothDevice> devices;
}

abstract interface class BluetoothRepository {
  Future<BluetoothSnapshot> inspect();
  Future<List<BluetoothDevice>> scan({Duration duration});
  Stream<List<BluetoothDevice>> get discoveryResults;
  Future<void> startAdvertising();
  Future<void> stopAdvertising();
  Future<void> connect(String deviceId);
  Future<void> disconnect();
  Future<void> sendMessage(String message);
  Stream<String> get messages;
}
