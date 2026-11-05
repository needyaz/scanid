// On-device integration test for the native scan/OCR path the unit tests
// can't reach: does the platform actually decode a PDF417 barcode and OCR an
// MRZ off a real image? Runs synthetic, generated fixtures (no real personal
// data) through PlatformCaptureService on a booted simulator/device.
//
//   flutter test integration_test/scan_probe_test.dart -d <device-id>
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:scanid/scanid.dart';

import 'scan_fixtures.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const capture = PlatformCaptureService();

  test('native scan decodes a PDF417 driver license → AAMVA fields', () async {
    final payloads = await capture.recognizeBarcodes(base64Decode(dlPdf417Base64));
    // ignore: avoid_print
    print('PROBE pdf417 payloads=${payloads.length}');
    if (payloads.isEmpty) {
      // Apple Vision's barcode detection doesn't run on the iOS Simulator (the
      // OCR path does) — skip here; this verifies on a real device or an
      // Android emulator.
      markTestSkipped('no barcode scanner here (e.g. iOS Simulator)');
      return;
    }

    final fields =
        payloads.map(Aamva.parse).firstWhere((f) => f != null, orElse: () => null);
    // ignore: avoid_print
    print('PROBE aamva=$fields');
    expect(fields, isNotNull, reason: 'decoded payload should parse as AAMVA');
    expect(fields!['number'], 'S12345678');
    expect(fields['name'], 'Jane Lee Smith');
    expect(fields['date_of_birth'], '1990-05-15');
    expect(fields['expires'], '2028-05-15');
  });

  test('native OCR reads a passport MRZ → parsed fields', () async {
    final ocr = await capture.recognize(base64Decode(passportMrzBase64));
    // ignore: avoid_print
    print('PROBE ocr=${ocr.fullText.replaceAll("\n", " | ")}');
    final mrz = Mrz.parse(ocr.fullText);
    // ignore: avoid_print
    print('PROBE mrz name=${mrz?.fullName} number=${mrz?.documentNumber}');
    expect(mrz, isNotNull, reason: 'OCR should read a parseable MRZ');
    expect(mrz!.fullName.toLowerCase(), contains('eriksson'));
  });
}
