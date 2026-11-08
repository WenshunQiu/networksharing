import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

enum AppLogLevel { debug, info, warning, error }

/// Structured file logger. Event fields must never contain credentials or
/// message bodies so logs can later be exported without protocol redaction.
class AppLogger {
  AppLogger({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  static final AppLogger instance = AppLogger();
  final Future<Directory> Function() _directoryProvider;
  static const maxFileBytes = 2 * 1024 * 1024;
  Future<File>? _fileFuture;
  Future<void> _tail = Future<void>.value();

  /// Waits for queued records before export or orderly shutdown.
  Future<void> flush() => _tail;

  Future<String?> get filePath async {
    try {
      return (await _file()).path;
    } catch (_) {
      return null;
    }
  }

  Future<String> exportableLogText() async {
    await flush();
    final current = await _file();
    final backup = File('${current.path}.1');
    final parts = <String>[];
    if (await backup.exists()) parts.add(await backup.readAsString());
    if (await current.exists()) parts.add(await current.readAsString());
    return parts.join();
  }

  void debug(
    String component,
    String event, [
    Map<String, Object?> fields = const {},
  ]) => _write(AppLogLevel.debug, component, event, fields);

  void info(
    String component,
    String event, [
    Map<String, Object?> fields = const {},
  ]) => _write(AppLogLevel.info, component, event, fields);

  void warning(
    String component,
    String event, [
    Map<String, Object?> fields = const {},
  ]) => _write(AppLogLevel.warning, component, event, fields);

  void error(
    String component,
    String event, [
    Map<String, Object?> fields = const {},
  ]) => _write(AppLogLevel.error, component, event, fields);

  void _write(
    AppLogLevel level,
    String component,
    String event,
    Map<String, Object?> fields,
  ) {
    final record = <String, Object?>{
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'level': level.name,
      'component': component,
      'event': event,
      'platform': defaultTargetPlatform.name,
      'fields': fields,
    };
    debugPrint('[${level.name}] $component.$event ${jsonEncode(fields)}');
    _tail = _tail.then((_) async {
      try {
        final file = await _file();
        final encoded = '${jsonEncode(record)}\n';
        final length = await file.length();
        if (length + utf8.encode(encoded).length > maxFileBytes) {
          final backup = File('${file.path}.1');
          if (await backup.exists()) await backup.delete();
          if (await file.exists()) await file.rename(backup.path);
          await _newFile();
        }
        await (await _file()).writeAsString(
          encoded,
          mode: FileMode.append,
          flush: true,
        );
      } catch (error) {
        debugPrint('[warning] logger.file_write_failed $error');
      }
    });
  }

  Future<File> _file() => _fileFuture ??= _newFile();

  Future<File> _newFile() async {
    Directory directory;
    try {
      directory = await _directoryProvider();
    } catch (error) {
      final fallback = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}NetworkSharing',
      );
      await fallback.create(recursive: true);
      debugPrint(
        '[warning] logger.support_path_unavailable ${error.runtimeType}; using temp directory',
      );
      directory = fallback;
    }
    final logDirectory = Directory(
      '${directory.path}${Platform.pathSeparator}logs',
    );
    await logDirectory.create(recursive: true);
    final file = File(
      '${logDirectory.path}${Platform.pathSeparator}networksharing.log',
    );
    if (!await file.exists()) await file.create();
    _fileFuture = Future<File>.value(file);
    return file;
  }
}
