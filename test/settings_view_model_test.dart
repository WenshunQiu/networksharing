import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:networksharing/domain/app_settings.dart';
import 'package:networksharing/features/settings/settings_repository.dart';
import 'package:networksharing/features/settings/settings_view_model.dart';

class ControlledSettingsRepository implements SettingsRepository {
  AppSettings stored = const AppSettings();
  bool readFails = false;
  bool writeFails = false;
  Completer<void>? pendingWrite;

  @override
  Future<AppSettings> load() async {
    if (readFails) throw StateError('read failed');
    return stored;
  }

  @override
  Future<void> save(AppSettings settings) async {
    await pendingWrite?.future;
    if (writeFails) throw StateError('write failed');
    stored = settings;
  }
}

void main() {
  test(
    'save failure restores previous values and reload permits retry',
    () async {
      final repository = ControlledSettingsRepository();
      final vm = SettingsViewModel(repository);
      await Future<void>.delayed(Duration.zero);
      repository.writeFails = true;
      await vm.update(vm.settings.copyWith(idleTimeoutMinutes: 30));
      expect(vm.settings.idleTimeoutMinutes, 10);
      expect(vm.error, isNotNull);
      repository.writeFails = false;
      await vm.load();
      await vm.update(vm.settings.copyWith(idleTimeoutMinutes: 30));
      expect(repository.stored.idleTimeoutMinutes, 30);
      vm.dispose();
    },
  );

  test(
    'read failure prevents defaults from overwriting stored preferences',
    () async {
      final repository = ControlledSettingsRepository()..readFails = true;
      final vm = SettingsViewModel(repository);
      await Future<void>.delayed(Duration.zero);
      await vm.update(vm.settings.copyWith(idleTimeoutMinutes: 30));
      expect(repository.stored.idleTimeoutMinutes, 10);
      expect(vm.error, isNotNull);
      vm.dispose();
    },
  );

  test(
    'pending save blocks another change and remains safe after disposal',
    () async {
      final repository = ControlledSettingsRepository();
      final vm = SettingsViewModel(repository);
      await Future<void>.delayed(Duration.zero);
      repository.pendingWrite = Completer<void>();
      final save = vm.update(vm.settings.copyWith(idleTimeoutMinutes: 30));
      await vm.update(vm.settings.copyWith(idleTimeoutMinutes: 60));
      expect(vm.settings.idleTimeoutMinutes, 30);
      vm.dispose();
      repository.pendingWrite!.complete();
      await save;
      expect(repository.stored.idleTimeoutMinutes, 30);
    },
  );
}
