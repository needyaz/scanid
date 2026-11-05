# scanid

Free, open-source on-device OCR, barcode scanning, and document-edge
detection for Flutter — plus decoders for the two formats that actually
matter for ID documents: **AAMVA** (the PDF417 barcode on the back of a
US/Canada driver's license) and **ICAO 9303 MRZ** (the machine-readable zone
on a passport or ID card).

Everything runs on-device — Apple Vision on iOS, ML Kit on Android. No
server calls, no API key, no license fee.

## Why this exists

Scanning a driver's license or passport is a bounded, publicly documented
problem (the AAMVA and ICAO specs are both open standards), but the
commercial SDKs that solve it charge an annual license fee for what is, at
its core, OCR + barcode decoding you can already get for free from the
platform. This package is that — the parsing logic, tested against real
jurisdiction quirks (not just the textbook examples), wrapped in a normal
Flutter plugin.

**What it does:**
- On-device text recognition (`recognize`)
- On-device barcode decoding, including PDF417 (`recognizeBarcodes`)
- Document-edge detection to seed a crop UI (`detectDocumentRect`)
- `Aamva.parse` — AAMVA barcode payload → structured fields (name, DOB,
  address, license class, …), handling real-world jurisdiction differences
  (legacy single-field names, letter-coded sex, CCYYMMDD vs MMDDCCYY dates)
- `Mrz.parse` — TD1/TD2/TD3 MRZ → structured, check-digit-validated fields,
  with OCR-artifact repair for the confusables real scanners actually produce

**What it deliberately does NOT do:** fraud detection, liveness checks, or
document-authenticity verification. If you need those, you need a different
(and probably paid) product — this is a parser, not a KYC/identity-
verification platform.

## Usage

```dart
import 'package:scanid/scanid.dart';

const capture = PlatformCaptureService();

// Driver's license (PDF417 barcode on the back)
final payloads = await capture.recognizeBarcodes(imageBytes);
final fields = payloads
    .map(Aamva.parse)
    .firstWhere((f) => f != null, orElse: () => null);
// fields?['name'], fields?['date_of_birth'], fields?['address'], ...

// Passport / ID card (MRZ)
final ocr = await capture.recognize(imageBytes);
final mrz = Mrz.parse(ocr.fullText);
// mrz?.fullName, mrz?.documentNumber, mrz?.numberValid, ...
```

In tests, use `FakeCaptureService` instead of `PlatformCaptureService` —
no native dependency, deterministic canned results.

## Platform notes

- **iOS**: uses the system `Vision` framework — no extra Podfile setup
  needed. Barcode detection does **not** run on the iOS Simulator (text
  recognition does); test the barcode path on a real device or an Android
  emulator.
- **Android**: pulls in ML Kit's `text-recognition` and `barcode-scanning`
  libraries automatically via this plugin's own Gradle dependencies — no
  changes needed in a consuming app's `build.gradle`.

## License

MIT — see `LICENSE`.
