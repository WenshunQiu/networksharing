enum ConnectivityState { online, offline }

class ConnectivitySnapshot {
  const ConnectivitySnapshot({
    required this.state,
    required this.checkedAt,
    this.reachableHosts = const {},
  });
  final ConnectivityState state;
  final DateTime checkedAt;
  final Set<String> reachableHosts;
}

abstract interface class ConnectivityRepository {
  Future<ConnectivitySnapshot> check();
}
