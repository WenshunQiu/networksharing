import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../domain/connectivity.dart';

class HttpConnectivityRepository implements ConnectivityRepository {
  @override
  Future<ConnectivitySnapshot> check() async {
    final hosts = await Future.wait([
      _canReach('www.baidu.com'),
      _canReach('www.google.com'),
    ]);
    final reachable = <String>{
      if (hosts[0]) 'www.baidu.com',
      if (hosts[1]) 'www.google.com',
    };
    return ConnectivitySnapshot(
      state: reachable.isNotEmpty
          ? ConnectivityState.online
          : ConnectivityState.offline,
      checkedAt: DateTime.now(),
      reachableHosts: reachable,
    );
  }

  Future<bool> _canReach(String host) async {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return _canReachWithCurl(host);
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final request = await client
          .getUrl(Uri.https(host, '/'))
          .timeout(const Duration(seconds: 5));
      request.followRedirects = true;
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      await response.drain<void>().timeout(const Duration(seconds: 2));
      return response.statusCode >= 200 && response.statusCode < 500;
    } on IOException {
      return false;
    } on TimeoutException {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> _canReachWithCurl(String host) async {
    try {
      final result = await Process.run('curl.exe', [
        '--location',
        '--silent',
        '--show-error',
        '--output',
        'NUL',
        '--max-time',
        '6',
        '--write-out',
        '%{http_code}',
        'https://$host/',
      ]).timeout(const Duration(seconds: 8));
      final code = int.tryParse('${result.stdout}'.trim());
      return result.exitCode == 0 && code != null && code >= 200 && code < 500;
    } on ProcessException {
      return false;
    } on TimeoutException {
      return false;
    }
  }
}
