/// The AAMVA driver-license barcode parser. Uses a representative PDF417 payload
/// (the format a scanner returns from the back of a US license).
library;

import 'package:test/test.dart';
import 'package:scanid/src/aamva.dart';

void main() {
  const payload = '@\n\rANSI 636000090002DL00410267ZV03080026'
      'DAQD12345678\n'
      'DCSDOE\n'
      'DACJOHN\n'
      'DADQUINCY\n'
      'DBB01311985\n'
      'DBA01312027\n'
      'DBC1\n'
      'DCAD\n'
      'DAG123 MAIN ST\n'
      'DAIANYTOWN\n'
      'DAJCA\n'
      'DAK90001      \n\r';

  test('parses the key fields from an AAMVA DL payload', () {
    final f = Aamva.parse(payload)!;
    expect(f['number'], 'D12345678');
    expect(f['name'], 'John Quincy Doe');
    expect(f['date_of_birth'], '1985-01-31'); // MMDDCCYY → ISO
    expect(f['expires'], '2027-01-31');
    expect(f['sex'], 'M'); // DBC 1
    expect(f['class'], 'D');
    expect(f['address'], '123 Main St, Anytown CA');
  });

  test('handles the Canadian CCYYMMDD date order', () {
    final f = Aamva.parse(payload.replaceFirst('DBB01311985', 'DBB19850131'))!;
    expect(f['date_of_birth'], '1985-01-31');
  });

  test('returns null for non-AAMVA text', () {
    expect(Aamva.parse('just some scanned text'), isNull);
  });

  // Real-jurisdiction shapes (structure from IdParser's per-state fixtures).
  test('California: class glued into the header line', () {
    const ca = 'ANSI 636014040002DL00410278ZC03190034DLDCAC\n'
        'DBA07052019\nDCSHARPER\nDACELIJAH\nDADMASON\n'
        'DBB07051973\nDBC1\nDAQF1485768\n';
    final f = Aamva.parse(ca)!;
    expect(f['number'], 'F1485768');
    expect(f['name'], 'Elijah Mason Harper');
    expect(f['class'], 'C'); // DCA glued after the DL designator
    expect(f['date_of_birth'], '1973-07-05');
  });

  test('Alberta: letter sex (F), CCYYMMDD dates, dashed number', () {
    const ab = 'ANSI 990876030001DLabacDLDCSMOTORIST\n'
        'DACMARY\nDADSMITH\nDAQ123400-056\nDBCF\n'
        'DBB19930204\nDBA20190108\n';
    final f = Aamva.parse(ab)!;
    expect(f['number'], '123400-056');
    expect(f['sex'], 'F'); // DBC 'F', not '2'
    expect(f['date_of_birth'], '1993-02-04'); // CCYYMMDD
    expect(f['expires'], '2019-01-08');
  });

  test('an absent middle name is not matched inside another value (DADE)', () {
    // No DAD (middle) element. A street value contains the substring "DAD"
    // ("123 DADE COUNTY RD"). The old match-anywhere fallback read the middle
    // name as "E County Rd"; anchoring to a line start / the header prevents it.
    const p = '@\n\rANSI 636000090002DL00410267\n'
        'DAQD12345678\nDCSDOE\nDACJOHN\n'
        'DBB01311985\nDBA01312027\nDBC1\n'
        'DAG123 DADE COUNTY RD\nDAIMIAMI\nDAJFL\n';
    final f = Aamva.parse(p)!;
    expect(f['number'], 'D12345678');
    expect(f['name'], 'John Doe'); // no bogus middle from "DADE"
    expect(f['address'], '123 Dade County Rd, Miami FL');
  });

  test('Connecticut legacy: name from a single DAA field', () {
    const ct = '@\n6AAMVA6360060101DL00290182DAACORTEZ,PABLO,LUIS RODRIGUEZ,JR\n'
        'DAQ227881513\nDBA20221007\nDBB19761007\nDBC1\n';
    final f = Aamva.parse(ct)!;
    expect(f['number'], '227881513');
    expect(f['name'], 'Pablo Luis Rodriguez Cortez');
    expect(f['date_of_birth'], '1976-10-07');
  });
}
