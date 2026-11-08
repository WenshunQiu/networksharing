import 'dart:async';
import 'dart:io';

import 'package:networksharing/data/app_logger.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.path);
  final String path;
  @override
  Future<String> getApplicationSupportPath() async => path;
}

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final directory = await Directory.systemTemp.createTemp(
    'networksharing-test-',
  );
  PathProviderPlatform.instance = _TestPaths(directory.path);
  try {
    await testMain();
  } finally {
    await AppLogger.instance.flush();
    await directory.delete(recursive: true);
  }
}
