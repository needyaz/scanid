/// The capture service: platform-channel mapping and the fake.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scanid/scanid.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('scanid/capture');
  final image = Uint8List.fromList([1, 2, 3]);

  void mock(Future<Object?> Function(MethodCall) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  const service = PlatformCaptureService();

  test('recognize maps channel lines to text, confidence and box', () async {
    MethodCall? call;
    mock((c) async {
      call = c;
      return [
        {
          'text': 'HELLO',
          'confidence': 0.5,
          'box': {'left': 0.1, 'top': 0.2, 'width': 0.3, 'height': 0.4},
        },
        {'text': 'WORLD'},
      ];
    });
    final r = await service.recognize(image);
    expect(call!.method, 'recognizeText');
    expect(r.lines, hasLength(2));
    expect(r.lines[0].confidence, 0.5);
    expect(r.lines[0].box!.left, 0.1);
    expect(r.lines[0].box!.height, 0.4);
    expect(r.lines[1].confidence, 1.0);
    expect(r.lines[1].box, isNull);
    expect(r.fullText, 'HELLO\nWORLD');
  });

  test('recognize returns empty on null or platform errors', () async {
    mock((c) async => null);
    expect((await service.recognize(image)).lines, isEmpty);
    mock((c) async => throw PlatformException(code: 'x'));
    expect((await service.recognize(image)).lines, isEmpty);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    expect((await service.recognize(image)).lines, isEmpty);
  });

  test('recognizeBarcodes returns payloads or empty on failure', () async {
    mock((c) async => ['a', 'b']);
    expect(await service.recognizeBarcodes(image), ['a', 'b']);
    mock((c) async => null);
    expect(await service.recognizeBarcodes(image), isEmpty);
    mock((c) async => throw PlatformException(code: 'x'));
    expect(await service.recognizeBarcodes(image), isEmpty);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    expect(await service.recognizeBarcodes(image), isEmpty);
  });

  test('detectDocumentRect returns a rect or null on failure', () async {
    mock((c) async =>
        {'left': 0.1, 'top': 0.2, 'width': 0.5, 'height': 0.6});
    final r = await service.detectDocumentRect(image);
    expect([r!.left, r.top, r.width, r.height], [0.1, 0.2, 0.5, 0.6]);
    mock((c) async => null);
    expect(await service.detectDocumentRect(image), isNull);
    mock((c) async => throw PlatformException(code: 'x'));
    expect(await service.detectDocumentRect(image), isNull);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    expect(await service.detectDocumentRect(image), isNull);
  });

  test('the base CaptureService defaults barcodes and document rect',
      () async {
    final base = _Bare();
    expect(await base.recognizeBarcodes(image), isEmpty);
    expect(await base.detectDocumentRect(image), isNull);
  });

  test('FakeCaptureService returns canned results', () async {
    const rect = DocumentRect(0, 0, 1, 1);
    final fake = FakeCaptureService.lines(['one', 'two'],
        barcodes: ['code'], docRect: rect);
    expect((await fake.recognize(image)).fullText, 'one\ntwo');
    expect(await fake.recognizeBarcodes(image), ['code']);
    expect(await fake.detectDocumentRect(image), same(rect));
    expect(
        await const FakeCaptureService(OcrResult.empty)
            .detectDocumentRect(image),
        isNull);
  });
}

class _Bare extends CaptureService {
  @override
  Future<OcrResult> recognize(Uint8List imageBytes) async => OcrResult.empty;
}
