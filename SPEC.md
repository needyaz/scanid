# scanid — specification

On-device OCR, barcode scanning and document-edge detection for Flutter, plus
decoders for AAMVA driver-license barcodes and ICAO 9303 machine-readable
zones. Nothing is sent off the device. Requirement ids below match
`spec/requirements.tsv`.

Spec status: 28 requirements, 28 C (covered by a passing test), 0 U
(uncovered).

## Public API

Exported from `package:scanid/scanid.dart`: `Aamva`, `Mrz`, `CaptureService`,
`PlatformCaptureService`, `FakeCaptureService`, `OcrResult`, `OcrLine`,
`OcrBox`, `DocumentRect`.

## AAMVA (`Aamva.parse`)

`Aamva.parse(String)` decodes the PDF417 payload from the back of a US/Canada
driver license into a `Map<String, String>?`.

- SCN-AAMVA-001: Returns null unless the text contains `ANSI ` or `AAMVA`.
- SCN-AAMVA-002: Returns null when none of the document number, first name or last
  name can be found.
- SCN-AAMVA-003: A field is a 3-letter element code at the start of a line, or glued
  into the header line that carries `ANSI`/`AAMVA`. A code inside another
  value (e.g. `DADE` in a street name) is never matched.
- SCN-AAMVA-004: Blank values and `NONE` count as absent.
- SCN-AAMVA-005: Output keys, each present only when the data exists: `number`
  (DAQ), `name`, `date_of_birth` (DBB), `expires` (DBA), `sex`, `class` (DCA),
  `address`.
- SCN-AAMVA-006: `name` is first, middle, last, each title-cased. Last name comes
  from DCS or DAB; first from DAC or DCT; middle from DAD.
- SCN-AAMVA-007: Legacy payloads with no DCS/DAC use a single DAA field
  `LAST,FIRST,MIDDLE` for the name.
- SCN-AAMVA-008: Dates of 8 digits are read as MMDDCCYY, or CCYYMMDD when the first
  two digits exceed 12, and output as ISO `yyyy-mm-dd`. Invalid months or
  non-8-digit values are dropped.
- SCN-AAMVA-009: `sex` is `M` for `1`/`M` and `F` for `2`/`F`; anything else is
  omitted.
- SCN-AAMVA-010: `address` is `Street, City ST`, with street and city title-cased
  and the state kept as written.

## MRZ (`Mrz.parse`)

`Mrz.parse(String text, {int? nowYear})` finds a TD1 (3×30), TD2 (2×36) or TD3
(2×44) MRZ in OCR text and returns an `Mrz` or null. `Mrz` exposes
`documentType`, `documentNumber`, `surname`, `givenNames`, `nationality`,
`issuingCountry`, `sex`, `dateOfBirth`, `expiryDate`, `numberValid` and
`fullName`.

- SCN-MRZ-001: TD3 passport lines are parsed into all fields.
- SCN-MRZ-002: TD1 ID-card lines (name on line 3) are parsed.
- SCN-MRZ-003: TD2 lines (name on line 1) are parsed.
- SCN-MRZ-004: Surrounding visual text and stray spaces or punctuation in OCR lines
  are ignored.
- SCN-MRZ-005: Returns null when no MRZ is present.
- SCN-MRZ-006: `numberValid` reflects the ICAO 7-3-1 check digit of the document
  number; filler `<` is removed from the number.
- SCN-MRZ-007: A date whose own check digit fails, or whose day is impossible for
  its month (leap-aware), is returned as null; if both dates fail the result
  is null.
- SCN-MRZ-008: Dates are ISO. Birth years later than `nowYear`'s 2-digit year are
  1900s, otherwise 2000s; expiry is always 2000s.
- SCN-MRZ-009: `documentType` is the first MRZ character.
- SCN-MRZ-010: OCR repair: a filler fragment split onto its own line is rejoined;
  short lines are right-padded with `<`; `«`/`»` read as `<<` and `‹ › ( [ {`
  as `<`.
- SCN-MRZ-011: Country and nationality codes have digit look-alikes mapped to
  letters (0→O, 1→I, 2→Z, 5→S, 8→B).
- SCN-MRZ-012: Names are split at `<<` into surname and given names and
  title-cased; `fullName` is "Given Surname". Sex `<` becomes empty.

## Capture (`CaptureService`)

- SCN-CAP-001: `PlatformCaptureService.recognize` calls channel `scanid/capture`
  method `recognizeText` and returns lines with text, confidence (default 1.0)
  and normalized box; `OcrResult.fullText` joins line texts with newlines.
- SCN-CAP-002: `recognize` returns an empty result on a null reply,
  `PlatformException` or `MissingPluginException`.
- SCN-CAP-003: `recognizeBarcodes` returns the payload strings, or an empty list on
  null, `PlatformException` or `MissingPluginException`.
- SCN-CAP-004: `detectDocumentRect` returns a normalized top-left-origin
  `DocumentRect`, or null on null, `PlatformException` or
  `MissingPluginException`.
- SCN-CAP-005: The base `CaptureService` defaults `recognizeBarcodes` to an empty
  list and `detectDocumentRect` to null.
- SCN-CAP-006: `FakeCaptureService` returns canned OCR, barcodes and document rect;
  `FakeCaptureService.lines` builds one from text lines.
