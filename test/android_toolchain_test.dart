import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final files = [
    'android/build.gradle.kts',
    'example/android/settings.gradle.kts',
    'example/android/app/build.gradle.kts',
  ];

  test('android modules use AGP 9 built-in Kotlin', () {
    for (final f in files) {
      final text = File(f).readAsStringSync();
      expect(text, isNot(contains('kotlin-android')), reason: f);
      expect(text, isNot(contains('kotlinOptions')), reason: f);
      expect(text, isNot(contains('8.13.0')), reason: f);
    }
    expect(
      File('android/build.gradle.kts').readAsStringSync(),
      contains('com.android.tools.build:gradle:9.'),
    );
  });

  test('example app forces current androidx.test artifacts', () {
    final text = File('example/android/build.gradle.kts').readAsStringSync();
    expect(text, contains('espresso-core:3.6.1'));
    expect(text, contains('espresso-idling-resource:3.6.1'));
  });
}
