import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:networksharing/data/app_logger.dart';

void main() {
  test(
    'logger serializes concurrent records and rotates at the byte limit',
    () async {
      final directory = await Directory.systemTemp.createTemp('logger-test-');
      final logger = AppLogger(directoryProvider: () async => directory);
      try {
        final file = File((await logger.filePath)!);
        await file.writeAsBytes(List.filled(AppLogger.maxFileBytes, 32));
        logger.info('bluetooth', 'scan.started');
        logger.warning('bluetooth', 'scan.stopped', {'count': 2});
        await logger.flush();
        expect(await File('${file.path}.1').length(), AppLogger.maxFileBytes);
        final records = (await file.readAsLines())
            .map((line) => jsonDecode(line) as Map)
            .toList();
        expect(records.map((r) => r['event']), [
          'scan.started',
          'scan.stopped',
        ]);
        expect(records.last['fields'], {'count': 2});
        expect(records.first['timestamp'], endsWith('Z'));
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}
