import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:networksharing/domain/connectivity.dart';
import 'package:networksharing/features/status/connectivity_view_model.dart';

void main() {
  test('deduplicates checks and records the result', () async {
    final repository = PendingConnectivityRepository();
    final vm = ConnectivityViewModel(repository);
    await Future<void>.delayed(Duration.zero);
    final pending = vm.refresh();
    await vm.refresh();
    expect(repository.calls, 1);
    expect(vm.checking, isTrue);
    repository.result.complete(
      ConnectivitySnapshot(
        state: ConnectivityState.online,
        checkedAt: DateTime.now(),
        reachableHosts: const {'www.baidu.com'},
      ),
    );
    await pending;
    expect(vm.checking, isFalse);
    expect(vm.snapshot!.state, ConnectivityState.online);
    vm.dispose();
  });

  test('late failure after disposal does not notify listeners', () async {
    final repository = PendingConnectivityRepository();
    final vm = ConnectivityViewModel(repository);
    await Future<void>.delayed(Duration.zero);
    final pending = vm.refresh();
    vm.dispose();
    repository.result.completeError(StateError('unavailable'));
    await pending;
  });
}

class PendingConnectivityRepository implements ConnectivityRepository {
  final result = Completer<ConnectivitySnapshot>();
  int calls = 0;
  @override
  Future<ConnectivitySnapshot> check() {
    calls++;
    return result.future;
  }
}
