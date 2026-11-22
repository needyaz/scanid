# scanid — specification

On-device OCR, barcode scanning and document-edge detection for Flutter, plus
decoders for AAMVA driver-license barcodes and ICAO 9303 machine-readable
zones. Nothing is sent off the device. Requirement ids below match
`spec/requirements.tsv`.

## Public API

Exported from `package:scanid/scanid.dart`: `Aamva`, `Mrz`, `CaptureService`,
`PlatformCaptureService`, `FakeCaptureService`, `OcrResult`, `OcrLine`,
`OcrBox`, `DocumentRect`.

## AAMVA (`Aamva.parse`)

`Aamva.parse(String)` decodes the PDF417 payload from the back of a US/Canada
driver license into a `Map<String, String>?`.

- AAMVA-1: Returns null unless the text contains `ANSI ` or `AAMVA`.
- AAMVA-2: Returns null when none of the document number, first name or last
  name can be found.
- AAMVA-3: A field is a 3-letter element code at the start of a line, or glued
  into the header line that carries `ANSI`/`AAMVA`. A code inside another
  value (e.g. `DADE` in a street name) is never matched.
- AAMVA-4: Blank values and `NONE` count as absent.
- AAMVA-5: Output keys, each present only when the data exists: `number`
  (DAQ), `name`, `date_of_birth` (DBB), `expires` (DBA), `sex`, `class` (DCA),
  `address`.
- AAMVA-6: `name` is first, middle, last, each title-cased. Last name comes
  from DCS or DAB; first from DAC or DCT; middle from DAD.
- AAMVA-7: Legacy payloads with no DCS/DAC use a single DAA field
  `LAST,FIRST,MIDDLE` for the name.
- AAMVA-8: Dates of 8 digits are read as MMDDCCYY, or CCYYMMDD when the first
  two digits exceed 12, and output as ISO `yyyy-mm-dd`. Invalid months or
  non-8-digit values are dropped.
- AAMVA-9: `sex` is `M` for `1`/`M` and `F` for `2`/`F`; anything else is
  omitted.
- AAMVA-10: `address` is `Street, City ST`, with street and city title-cased
  and the state kept as written.

## MRZ (`Mrz.parse`)

`Mrz.parse(String text, {int? nowYear})` finds a TD1 (3×30), TD2 (2×36) or TD3
(2×44) MRZ in OCR text and returns an `Mrz` or null. `Mrz` exposes
`documentType`, `documentNumber`, `surname`, `givenNames`, `nationality`,
`issuingCountry`, `sex`, `dateOfBirth`, `expiryDate`, `numberValid` and
`fullName`.

- MRZ-1: TD3 passport lines are parsed into all fields.
- MRZ-2: TD1 ID-card lines (name on line 3) are parsed.
- MRZ-3: TD2 lines (name on line 1) are parsed.
- MRZ-4: Surrounding visual text and stray spaces or punctuation in OCR lines
  are ignored.
- MRZ-5: Returns null when no MRZ is present.
- MRZ-6: `numberValid` reflects the ICAO 7-3-1 check digit of the document
  number; filler `<` is removed from the number.
- MRZ-7: A date whose own check digit fails, or whose day is impossible for
  its month (leap-aware), is returned as null; if both dates fail the result
  is null.
- MRZ-8: Dates are ISO. Birth years later than `nowYear`'s 2-digit year are
  1900s, otherwise 2000s; expiry is always 2000s.
- MRZ-9: `documentType` is the first MRZ character.
- MRZ-10: OCR repair: a filler fragment split onto its own line is rejoined;
  short lines are right-padded with `<`; `«`/`»` read as `<<` and `‹ › ( [ {`
  as `<`.
- MRZ-11: Country and nationality codes have digit look-alikes mapped to
  letters (0→O, 1→I, 2→Z, 5→S, 8→B).
- MRZ-12: Names are split at `<<` into surname and given names and
  title-cased; `fullName` is "Given Surname". Sex `<` becomes empty.

## Capture (`CaptureService`)

- CAP-1: `PlatformCaptureService.recognize` calls channel `scanid/capture`
  method `recognizeText` and returns lines with text, confidence (default 1.0)
  and normalized box; `OcrResult.fullText` joins line texts with newlines.
- CAP-2: `recognize` returns an empty result on a null reply,
  `PlatformException` or `MissingPluginException`.
- CAP-3: `recognizeBarcodes` returns the payload strings, or an empty list on
  null, `PlatformException` or `MissingPluginException`.
- CAP-4: `detectDocumentRect` returns a normalized top-left-origin
  `DocumentRect`, or null on null, `PlatformException` or
  `MissingPluginException`.
- CAP-5: The base `CaptureService` defaults `recognizeBarcodes` to an empty
  list and `detectDocumentRect` to null.
- CAP-6: `FakeCaptureService` returns canned OCR, barcodes and document rect;
  `FakeCaptureService.lines` builds one from text lines.
