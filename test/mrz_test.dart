/// The MRZ (passport machine-readable zone) parser. Uses the canonical ICAO 9303
/// TD3 sample (valid check digits) so the parse is unambiguous.
library;

import 'package:test/test.dart';
import 'package:scanid/src/mrz.dart';

void main() {
  // ICAO 9303 specimen — Anna Maria Eriksson, Utopia.
  const sample = 'P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<\n'
      'L898902C36UTO7408122F1204159ZE184226B<<<<<10';

  test('parses every field from a TD3 passport MRZ', () {
    final m = Mrz.parse(sample, nowYear: 2026)!;
    expect(m.documentNumber, 'L898902C3');
    expect(m.numberValid, isTrue); // check digit validated
    expect(m.surname, 'Eriksson');
    expect(m.givenNames, 'Anna Maria');
    expect(m.fullName, 'Anna Maria Eriksson');
    expect(m.nationality, 'UTO');
    expect(m.issuingCountry, 'UTO');
    expect(m.sex, 'F');
    expect(m.dateOfBirth, '1974-08-12'); // YY 74 > 26 → 1900s
    expect(m.expiryDate, '2012-04-15'); // expiry → 2000s
  });

  test('tolerates surrounding visual text and OCR spacing', () {
    final text = 'PASSPORT\nUNITED STATES\n'
        'P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<\n'
        'L898902C3 6UTO7408122F1204159ZE184226B<<<<<10\n'
        'random footer';
    final m = Mrz.parse(text, nowYear: 2026);
    expect(m, isNotNull);
    expect(m!.fullName, 'Anna Maria Eriksson');
  });

  test('parses a TD1 ID card MRZ (3×30, name on line 3)', () {
    const td1 = 'I<UTOD231458907<<<<<<<<<<<<<<<\n'
        '7408122F1204159UTO<<<<<<<<<<<6\n'
        'ERIKSSON<<ANNA<MARIA<<<<<<<<<<';
    final m = Mrz.parse(td1, nowYear: 2026)!;
    expect(m.documentNumber, 'D23145890');
    expect(m.numberValid, isTrue);
    expect(m.fullName, 'Anna Maria Eriksson');
    expect(m.nationality, 'UTO');
    expect(m.sex, 'F');
    expect(m.dateOfBirth, '1974-08-12');
    expect(m.expiryDate, '2012-04-15');
  });

  test('parses a TD2 MRZ (2×36, name on line 1)', () {
    const td2 = 'I<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<\n'
        'D231458907UTO7408122F1204159<<<<<<<0';
    final m = Mrz.parse(td2, nowYear: 2026)!;
    expect(m.documentNumber, 'D23145890');
    expect(m.fullName, 'Anna Maria Eriksson');
    expect(m.dateOfBirth, '1974-08-12');
    expect(m.expiryDate, '2012-04-15');
  });

  test('real-world TD3 (Canada): filler in the document number', () {
    const can = 'P<CANMARTIN<<SARAH<<<<<<<<<<<<<<<<<<<<<<<<<<\n'
        'ZE000509<9CAN8501019F2301147<<<<<<<<<<<<<<08';
    final m = Mrz.parse(can, nowYear: 2026)!;
    expect(m.documentNumber, 'ZE000509'); // trailing filler stripped
    expect(m.numberValid, isTrue);
    expect(m.fullName, 'Sarah Martin');
    expect(m.nationality, 'CAN');
    expect(m.dateOfBirth, '1985-01-01');
    expect(m.expiryDate, '2023-01-14');
  });

  test('real-world TD1 (Spain ID): double surname', () {
    const esp = 'IDESPBAA000589599999999R<<<<<<\n'
        '8001014F2501017ESP<<<<<<<<<<<7\n'
        'ESPANOLA<ESPANOLA<<CARMEN<<<<<';
    final m = Mrz.parse(esp, nowYear: 2026)!;
    expect(m.surname, 'Espanola Espanola'); // two surnames, '<' → space
    expect(m.givenNames, 'Carmen');
    expect(m.nationality, 'ESP');
    expect(m.dateOfBirth, '1980-01-01');
  });

  test('returns null when there is no MRZ', () {
    expect(Mrz.parse('Just a grocery list\nmilk eggs bread'), isNull);
  });

  test('flags a bad document-number check digit', () {
    // Corrupt the doc-number check digit (6 → 5).
    final bad = sample.replaceFirst('L898902C36', 'L898902C35');
    final m = Mrz.parse(bad, nowYear: 2026)!;
    expect(m.numberValid, isFalse);
  });

  test('drops the DOB when its own check digit fails (keeps the expiry)', () {
    // Corrupt the DOB check digit (…740812[2]F → …740812[3]F). MRZ fields
    // override the LLM as "verified", so a date that fails its check must be
    // withheld, not emitted wrong.
    final bad = sample.replaceFirst('7408122F', '7408123F');
    final m = Mrz.parse(bad, nowYear: 2026)!;
    expect(m.dateOfBirth, isNull); // check digit rejects the date
    expect(m.expiryDate, '2012-04-15'); // expiry untouched → doc still parses
  });

  test('drops a DOB with an impossible day even if the check digit matches', () {
    // Replace the DOB + its check with 740845 (day 45) + its VALID check 4 — so
    // the check passes but the day is impossible. Guards an OCR slip that lands
    // on a coincidentally-valid check digit.
    final bad = sample.replaceFirst('7408122', '7408454');
    final m = Mrz.parse(bad, nowYear: 2026)!;
    expect(m.dateOfBirth, isNull); // day 45 is out of range
    expect(m.expiryDate, '2012-04-15');
  });

  test('exposes the document type (P for a passport)', () {
    expect(Mrz.parse(sample, nowYear: 2026)!.documentType, 'P');
  });

  test('survives real OCR artifacts on a TD1: split filler, short name line, '
      'O→0 in the country code', () {
    // Verbatim shape Apple Vision produced off a rendered TD1 card (the
    // on-device doc-types probe): the country's O read as zero, the name
    // line's trailing filler dropped/split onto its own line.
    const ocr = 'I<UT0D231458907<<<<<<<<<<<<<<<\n'
        '7408122F1204159UTO<<<<<<<<<<<6\n'
        'ERIKSSON<<ANNA<MARIA<<<<<\n'
        '<<<<';
    final m = Mrz.parse(ocr, nowYear: 2026)!;
    expect(m.documentType, 'I');
    expect(m.documentNumber, 'D23145890');
    expect(m.numberValid, isTrue);
    expect(m.fullName, 'Anna Maria Eriksson');
    expect(m.issuingCountry, 'UTO'); // 0 → O restored (letters-only field)
    expect(m.dateOfBirth, '1974-08-12');
  });

  test("survives ML Kit's guillemet/paren confusables for '<' filler", () {
    // Verbatim shape ML Kit produced off the same rendered TD1 card on the
    // Android emulator: '<<' read as '«', '<' as '('.
    const ocr = 'I<UTOD231458907<<<<«\n'
        '(<<<\n'
        '7408122F1204159UTO<<<<<«<«««<6\n'
        'ERIKSSON<<ANNA<MARIA<<«<«««««<';
    final m = Mrz.parse(ocr, nowYear: 2026)!;
    expect(m.documentNumber, 'D23145890');
    expect(m.numberValid, isTrue);
    expect(m.fullName, 'Anna Maria Eriksson');
    expect(m.dateOfBirth, '1974-08-12');
  });

  test('survives a fully dropped trailing filler on the TD1 name line', () {
    const ocr = 'I<UTOD231458907<<<<<<<<<<<<<<<\n'
        '7408122F1204159UTO<<<<<<<<<<<6\n'
        'ERIKSSON<<ANNA<MARIA<<<<'; // 24 chars — filler lost entirely
    final m = Mrz.parse(ocr, nowYear: 2026)!;
    expect(m.fullName, 'Anna Maria Eriksson');
    expect(m.documentNumber, 'D23145890');
  });
}
