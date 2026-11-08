enum ConnectivityState { online, unknown }

class ConnectivitySnapshot {
  const ConnectivitySnapshot({required this.state, required this.checkedAt});
  final ConnectivityState state;
  final DateTime checkedAt;
}

abstract interface class ConnectivityRepository {
  Future<ConnectivitySnapshot> check();
}
