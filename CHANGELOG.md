## 0.1.1

- Add pub.dev topics (`ocr`, `barcode`, `scanner`, `mrz`, `document-scanner`) for discoverability. No code changes.

## 0.1.0

- Initial release. On-device OCR, barcode scanning, and document-edge
  detection (`CaptureService`/`PlatformCaptureService`/`FakeCaptureService`),
  plus `Aamva.parse` (AAMVA PDF417 driver's-license decode, including real
  jurisdiction quirks) and `Mrz.parse` (ICAO 9303 MRZ decode, TD1/TD2/TD3,
  check-digit validated, with OCR-artifact repair). iOS via Apple Vision,
  Android via ML Kit.
