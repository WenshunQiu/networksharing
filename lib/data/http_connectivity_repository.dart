import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/connectivity.dart';

/// A single endpoint can prove connectivity, but cannot prove total outage.
class HttpConnectivityRepository implements ConnectivityRepository {
  @override
  Future<ConnectivitySnapshot> check() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    var state = ConnectivityState.unknown;
    try {
      final request = await client
          .getUrl(Uri.parse('https://www.msftconnecttest.com/connecttest.txt'))
          .timeout(const Duration(seconds: 6));
      request.followRedirects = false;
      final response = await request.close().timeout(
        const Duration(seconds: 6),
      );
      if (response.statusCode == HttpStatus.ok) {
        final body = await response
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 3));
        if (body.trim() == 'Microsoft Connect Test') {
          state = ConnectivityState.online;
        }
      }
    } on IOException {
      state = ConnectivityState.unknown;
    } on TimeoutException {
      state = ConnectivityState.unknown;
    } finally {
      client.close(force: true);
    }
    return ConnectivitySnapshot(state: state, checkedAt: DateTime.now());
  }
}
