import 'dart:async';

import 'package:flutter/foundation.dart';

import 'pairing_repository.dart';

enum PairingStatus { idle, pairing, paired, error }

class PairingViewModel extends ChangeNotifier {
  PairingViewModel({required this._repository}) {
    regenerateCode();
  }

  static const codeLifetime = Duration(minutes: 5);
  final PairingRepository _repository;
  bool _disposed = false;
  int _operation = 0;
  Timer? _expiryTimer;
  String pairingCode = '';
  String enteredCode = '';
  DateTime? expiresAt;
  String? sessionId;
  PairingStatus status = PairingStatus.idle;
  String? message;
  bool isShowingCode = true;

  Duration get remaining {
    final expiry = expiresAt;
    if (expiry == null) return Duration.zero;
    final value = expiry.difference(DateTime.now());
    return value.isNegative ? Duration.zero : value;
  }

  Future<void> regenerateCode() async {
    if (_disposed || status == PairingStatus.pairing) return;
    final operation = ++_operation;
    status = PairingStatus.pairing;
    message = null;
    notifyListeners();
    try {
      final session = await _repository.createSession();
      if (_disposed || operation != _operation) return;
      sessionId = session.sessionId;
      pairingCode = session.code;
      expiresAt = session.expiresAt;
    } catch (_) {
      if (_disposed || operation != _operation) return;
      status = PairingStatus.error;
      message = '无法生成配对码，请检查本地 Rust 服务。';
      notifyListeners();
      return;
    }
    status = PairingStatus.idle;
    message = null;
    _expiryTimer?.cancel();
    _expiryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (remaining == Duration.zero) {
        _expiryTimer?.cancel();
        if (isShowingCode && status != PairingStatus.pairing) {
          status = PairingStatus.error;
          message = '配对码已过期，请重新生成。';
        }
      }
      notifyListeners();
    });
    notifyListeners();
  }

  void setEnteredCode(String value) {
    if (_disposed || status == PairingStatus.pairing) return;
    enteredCode = value.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
    if (enteredCode.length > 6) enteredCode = enteredCode.substring(0, 6);
    message = null;
    notifyListeners();
  }

  void setShowingCode(bool value) {
    if (_disposed) return;
    _operation++;
    isShowingCode = value;
    status = PairingStatus.idle;
    message = null;
    notifyListeners();
  }

  Future<void> submitCode() async {
    if (_disposed || status == PairingStatus.pairing) return;
    if (enteredCode.length != 6) {
      status = PairingStatus.error;
      message = '请输入完整的 6 位配对码。';
      notifyListeners();
      return;
    }
    status = PairingStatus.pairing;
    final operation = ++_operation;
    message = null;
    notifyListeners();
    try {
      final result = await _repository
          .pair(enteredCode)
          .timeout(const Duration(seconds: 30));
      if (_disposed || operation != _operation) return;
      status = result.success ? PairingStatus.paired : PairingStatus.error;
      message = result.message;
    } on TimeoutException {
      if (_disposed || operation != _operation) return;
      status = PairingStatus.error;
      message = '配对请求超时，请检查设备后重试。';
    } catch (_) {
      if (_disposed || operation != _operation) return;
      status = PairingStatus.error;
      message = '配对失败，请检查蓝牙连接后重试。';
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _operation++;
    _expiryTimer?.cancel();
    super.dispose();
  }
}
