import 'package:flutter/foundation.dart';

import 'dart:async';

import '../../domain/connectivity.dart';

class ConnectivityViewModel extends ChangeNotifier {
  ConnectivityViewModel(this._repository) {
    unawaited(refresh());
    _poller = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(refresh()),
    );
  }
  final ConnectivityRepository _repository;
  ConnectivitySnapshot? snapshot;
  bool checking = false;
  bool _disposed = false;
  Timer? _poller;

  Future<void> refresh() async {
    if (checking || _disposed) return;
    checking = true;
    notifyListeners();
    try {
      final result = await _repository.check();
      if (!_disposed) snapshot = result;
    } catch (_) {
      if (!_disposed) {
        snapshot = ConnectivitySnapshot(
          state: ConnectivityState.offline,
          checkedAt: DateTime.now(),
          reachableHosts: const {},
        );
      }
    } finally {
      if (!_disposed) {
        checking = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _poller?.cancel();
    super.dispose();
  }
}
