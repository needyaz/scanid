import 'package:flutter/services.dart';

/// A detected document's bounding box, normalized to `[0,1]` in image space with
/// a **top-left** origin. Used only as the *initial* rectangle for a confirm-
/// crop UI — the caller should always let the user adjust/accept it, so a loose
/// detection is fine.
class DocumentRect {
  final double left, top, width, height;
  const DocumentRect(this.left, this.top, this.width, this.height);
}

/// A recognized text element's bounding box, normalized to `[0,1]` in image
/// space with a **top-left** origin — so it can be overlaid on the displayed
/// image regardless of scale.
class OcrBox {
  final double left, top, width, height;
  const OcrBox(this.left, this.top, this.width, this.height);
}

/// One recognized line of text from on-device OCR, with its position on the
/// image ([box]) when the platform provides it.
class OcrLine {
  final String text;
  final double confidence;
  final OcrBox? box;
  const OcrLine(this.text, {this.confidence = 1.0, this.box});
}

/// The result of recognizing text in an image — all produced on-device.
class OcrResult {
  final List<OcrLine> lines;
  const OcrResult(this.lines);

  /// The full recognized text, newline-joined.
  String get fullText => lines.map((l) => l.text).join('\n');

  static const empty = OcrResult([]);
}

/// On-device OCR, barcode scanning, and document-edge detection. Nothing ever
/// leaves the device — Apple Vision (iOS) / ML Kit (Android) run locally, and
/// the only thing that crosses the platform channel is the image bytes in and
/// recognized data out.
///
/// Use [FakeCaptureService] in tests, or anywhere real native capture isn't
/// available/needed (e.g. a simulator where barcode detection doesn't run).
abstract class CaptureService {
  Future<OcrResult> recognize(Uint8List imageBytes);

  /// Decode 2D barcodes from the image — chiefly a driver license's PDF417 (its
  /// AAMVA payload, see [Aamva.parse]). Returns the raw payload strings, or
  /// `[]` when there are none / the platform can't. Default no-op so fakes
  /// need not implement it.
  Future<List<String>> recognizeBarcodes(Uint8List imageBytes) async => const [];

  /// Detect a document/card in the image and return its bounding box (to seed
  /// a confirm-crop UI), or `null` when none is found / the platform can't.
  /// A caller should let the user confirm or adjust the rectangle before any
  /// crop is applied — this is a hint, never an automatic crop. Default no-op
  /// for fakes.
  Future<DocumentRect?> detectDocumentRect(Uint8List imageBytes) async => null;
}

/// Calls the native OCR/barcode/document-detect plugin over a [MethodChannel].
/// The native side (`ScanidPlugin.swift` / `ScanidPlugin.kt`) registers
/// `scanid/capture` and returns a list of `{text, confidence, box}` maps for
/// `recognizeText`, a list of payload strings for `recognizeBarcodes`, and a
/// `{left, top, width, height}` map or null for `detectDocumentRect`.
class PlatformCaptureService implements CaptureService {
  static const _channel = MethodChannel('scanid/capture');

  const PlatformCaptureService();

  @override
  Future<OcrResult> recognize(Uint8List imageBytes) async {
    try {
      final raw = await _channel.invokeListMethod<Map<dynamic, dynamic>>(
        'recognizeText',
        {'image': imageBytes},
      );
      if (raw == null) return OcrResult.empty;
      return OcrResult([
        for (final m in raw)
          OcrLine(
            (m['text'] as String?) ?? '',
            confidence: (m['confidence'] as num?)?.toDouble() ?? 1.0,
            box: _box(m['box']),
          ),
      ]);
    } on PlatformException {
      // One weird image must not throw the whole capture flow away. Same
      // graceful shape as the barcode/detect siblings: no text, flow proceeds.
      return OcrResult.empty;
    } on MissingPluginException {
      return OcrResult.empty;
    }
  }

  static OcrBox? _box(Object? b) {
    if (b is! Map) return null;
    final l = (b['left'] as num?)?.toDouble();
    final t = (b['top'] as num?)?.toDouble();
    final w = (b['width'] as num?)?.toDouble();
    final h = (b['height'] as num?)?.toDouble();
    if (l == null || t == null || w == null || h == null) return null;
    return OcrBox(l, t, w, h);
  }

  @override
  Future<List<String>> recognizeBarcodes(Uint8List imageBytes) async {
    try {
      final raw = await _channel
          .invokeListMethod<String>('recognizeBarcodes', {'image': imageBytes});
      return raw ?? const [];
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  @override
  Future<DocumentRect?> detectDocumentRect(Uint8List imageBytes) async {
    try {
      final m = await _channel.invokeMapMethod<String, dynamic>(
          'detectDocumentRect', {'image': imageBytes});
      if (m == null) return null;
      return DocumentRect(
        (m['left'] as num).toDouble(),
        (m['top'] as num).toDouble(),
        (m['width'] as num).toDouble(),
        (m['height'] as num).toDouble(),
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

/// Deterministic OCR for tests + simulators: returns canned results, either a
/// single fixed result or one built from raw lines. No native dependency.
class FakeCaptureService implements CaptureService {
  final OcrResult result;
  final List<String> barcodes;

  /// When non-null, [detectDocumentRect] returns this box; null models "no
  /// document detected" (the default).
  final DocumentRect? docRect;
  const FakeCaptureService(this.result,
      {this.barcodes = const [], this.docRect});

  /// Build a fake from raw lines of text.
  factory FakeCaptureService.lines(List<String> lines,
          {List<String> barcodes = const [], DocumentRect? docRect}) =>
      FakeCaptureService(OcrResult([for (final l in lines) OcrLine(l)]),
          barcodes: barcodes, docRect: docRect);

  @override
  Future<OcrResult> recognize(Uint8List imageBytes) async => result;

  @override
  Future<List<String>> recognizeBarcodes(Uint8List imageBytes) async =>
      barcodes;

  @override
  Future<DocumentRect?> detectDocumentRect(Uint8List imageBytes) async =>
      docRect;
}
