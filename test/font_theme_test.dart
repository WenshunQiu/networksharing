import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:networksharing/app/network_sharing_app.dart';

void main() {
  test('uses the platform Chinese system font families', () {
    expect(
      systemFontFamilyForPlatform(TargetPlatform.windows),
      'Microsoft YaHei UI',
    );
    expect(systemFontFamilyForPlatform(TargetPlatform.android), 'sans-serif');
  });
}
