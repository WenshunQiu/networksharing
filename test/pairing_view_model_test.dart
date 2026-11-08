import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:networksharing/features/pairing/pairing_repository.dart';
import 'package:networksharing/features/pairing/pairing_view_model.dart';

void main() {
  test(
    'duplicate requests are ignored and late results after disposal are safe',
    () async {
      final repository = PendingPairingRepository();
      final vm = PairingViewModel(repository: repository);
      await Future<void>.delayed(Duration.zero);
      vm.setEnteredCode('ABC234');
      final pending = vm.submitCode();
      await vm.submitCode();
      expect(repository.calls, 1);
      vm.dispose();
      repository.result.complete(
        const PairingResult(success: false, message: 'late'),
      );
      await pending;
    },
  );

  test('switching pairing mode invalidates the pending response', () async {
    final repository = PendingPairingRepository();
    final vm = PairingViewModel(repository: repository);
    await Future<void>.delayed(Duration.zero);
    vm.setEnteredCode('ABC234');
    final pending = vm.submitCode();
    vm.setShowingCode(true);
    repository.result.complete(
      const PairingResult(success: true, message: 'late'),
    );
    await pending;
    expect(vm.status, PairingStatus.idle);
    expect(vm.message, isNull);
    vm.dispose();
  });
  group('PairingViewModel', () {
    test('generates a six character code with an expiry', () async {
      final vm = PairingViewModel(repository: UnavailablePairingRepository());
      await Future<void>.delayed(Duration.zero);
      expect(vm.pairingCode, 'ABC234');
      expect(vm.remaining, greaterThan(Duration.zero));
      vm.dispose();
    });

    test('normalizes and limits entered code', () async {
      final vm = PairingViewModel(repository: UnavailablePairingRepository());
      await Future<void>.delayed(Duration.zero);
      vm.setEnteredCode('ab-cd12!x');
      expect(vm.enteredCode, 'ABCD12');
      vm.dispose();
    });

    test(
      'does not claim pairing when Bluetooth provider is unavailable',
      () async {
        final vm = PairingViewModel(repository: UnavailablePairingRepository());
        await Future<void>.delayed(Duration.zero);
        vm.setEnteredCode('ABC234');
        await vm.submitCode();
        expect(vm.status, PairingStatus.error);
        expect(vm.message, contains('蓝牙配对功能尚未接入'));
        vm.dispose();
      },
    );
  });
}

class PendingPairingRepository implements PairingRepository {
  @override
  Future<PairingCodeSession> createSession() async => PairingCodeSession(
    sessionId: 'test-session',
    code: 'ABC234',
    expiresAt: DateTime.now().add(const Duration(minutes: 5)),
  );
  final result = Completer<PairingResult>();
  int calls = 0;
  @override
  Future<PairingResult> pair(String code) {
    calls++;
    return result.future;
  }
}

class UnavailablePairingRepository implements PairingRepository {
  @override
  Future<PairingCodeSession> createSession() async => PairingCodeSession(
    sessionId: 'test-session',
    code: 'ABC234',
    expiresAt: DateTime.now().add(const Duration(minutes: 5)),
  );

  @override
  Future<PairingResult> pair(String code) async =>
      const PairingResult(success: false, message: '蓝牙配对功能尚未接入，请稍后再试。');
}
