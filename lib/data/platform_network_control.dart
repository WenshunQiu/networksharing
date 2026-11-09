import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_logger.dart';

/// Platform operations return confirmed state; credentials never enter logs.
class PlatformNetworkControl {
  static const _channel = MethodChannel('networksharing/debug');

  Future<Map<String, dynamic>> execute(
    String operation, {
    String? ssid,
    String? password,
  }) async {
    AppLogger.instance.info('network', 'operation.started', {
      'operation': operation,
    });
    try {
      final Map<String, dynamic> result;
      final arguments = <String, dynamic>{
        'operation': operation,
        'ssid': ssid,
        'password': password,
      };
      if (defaultTargetPlatform == TargetPlatform.windows) {
        final source = await rootBundle.loadString(
          'assets/windows_network.ps1',
        );
        // EncodedCommand holds only the static script. Secrets travel via stdin.
        final units = source.codeUnits;
        final encoded = base64Encode([
          for (final unit in units) ...[unit & 255, unit >> 8],
        ]);
        final process = await Process.start('powershell.exe', [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-EncodedCommand',
          encoded,
        ]);
        final stdout = process.stdout.transform(utf8.decoder).join();
        final stderr = process.stderr.transform(utf8.decoder).join();
        process.stdin.writeln(jsonEncode(arguments));
        await process.stdin.close();
        try {
          await process.exitCode.timeout(const Duration(seconds: 40));
        } on TimeoutException {
          process.kill();
          rethrow;
        }
        final output = await stdout;
        await stderr; // Consume errors without accidentally logging secrets.
        result = Map<String, dynamic>.from(jsonDecode(output) as Map);
      } else {
        result = Map<String, dynamic>.from(
          await _channel.invokeMapMethod<String, dynamic>(
                operation,
                arguments,
              ) ??
              {},
        );
      }
      AppLogger.instance.info('network', 'operation.completed', {
        'operation': operation,
        'success': result['success'],
        'enabled': result['enabled'],
        'message': result['message'],
      });
      if (result['success'] != true) {
        throw StateError(
          result['message']?.toString() ?? 'Platform operation failed',
        );
      }
      return result;
    } catch (error) {
      AppLogger.instance.error('network', 'operation.failed', {
        'operation': operation,
        'errorType': error.runtimeType.toString(),
      });
      rethrow;
    }
  }
}
