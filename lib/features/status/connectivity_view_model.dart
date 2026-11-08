import 'package:flutter/foundation.dart';

import '../../domain/connectivity.dart';

class ConnectivityViewModel extends ChangeNotifier {
  ConnectivityViewModel(this._repository);
  final ConnectivityRepository _repository;
  ConnectivitySnapshot? snapshot;
  bool checking = false;
  bool _disposed = false;

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
          state: ConnectivityState.unknown,
          checkedAt: DateTime.now(),
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
    super.dispose();
  }
}
