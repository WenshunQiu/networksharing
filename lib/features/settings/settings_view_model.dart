import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/app_settings.dart';
import 'settings_repository.dart';

class SettingsViewModel extends ChangeNotifier {
  SettingsViewModel(this._repository) {
    unawaited(load());
  }
  final SettingsRepository _repository;
  AppSettings settings = const AppSettings();
  bool loading = true;
  bool saving = false;
  String? error;
  bool _disposed = false;
  int _generation = 0;

  Future<void> load() async {
    if (_disposed || saving) return;
    final generation = ++_generation;
    loading = true;
    error = null;
    _notify();
    try {
      final loaded = await _repository.load();
      if (_disposed || generation != _generation) return;
      settings = loaded;
    } catch (_) {
      if (_disposed || generation != _generation) return;
      error = '读取设置失败，请重试。';
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> update(AppSettings next) async {
    if (_disposed || loading || saving || error != null || next == settings) {
      return;
    }
    final previous = settings;
    settings = next;
    saving = true;
    error = null;
    _notify();
    try {
      await _repository.save(next);
    } catch (_) {
      if (_disposed) return;
      settings = previous;
      error = '保存设置失败，已恢复之前的值。';
    } finally {
      if (!_disposed) {
        saving = false;
        _notify();
      }
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
