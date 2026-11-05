/// Free, open-source on-device OCR, barcode scanning, and document-edge
/// detection, plus AAMVA driver's-license and ICAO MRZ decoders.
///
/// Everything runs on-device (Apple Vision on iOS, ML Kit on Android) —
/// nothing is ever sent to a server, and there's no license fee.
///
/// Typical usage:
/// ```dart
/// const capture = PlatformCaptureService();
/// final payloads = await capture.recognizeBarcodes(imageBytes);
/// final fields = payloads.map(Aamva.parse).firstWhere(
///   (f) => f != null,
///   orElse: () => null,
/// );
///
/// final ocr = await capture.recognize(imageBytes);
/// final mrz = Mrz.parse(ocr.fullText);
/// ```
library;

export 'src/aamva.dart';
export 'src/mrz.dart';
export 'src/capture_service.dart';
