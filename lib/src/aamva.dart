/// Parses the **AAMVA** payload encoded in the PDF417 barcode on the back of a
/// US/Canada driver license or state ID into structured fields. Like the MRZ,
/// the barcode encodes the data exactly (3-letter element codes, each value
/// newline-terminated) — far more reliable than OCR of the printed front. The
/// barcode bytes come from a scanner ([CaptureService.recognizeBarcodes]); this
/// just decodes the payload string. Returns null if it isn't an AAMVA payload.
class Aamva {
  static Map<String, String>? parse(String data) {
    if (!data.contains('ANSI ') && !data.contains('AAMVA')) return null;

    // Each element is its 3-letter code + value up to the next line break. Look
    // for the code ONLY as a real element header: at the start of a line
    // (multiline `^`), or glued into the compact subfile-header line (the line
    // carrying ANSI/AAMVA — e.g. "DLDCAC", "…DL00290182DAACORTEZ"). Never match
    // the code mid-value (a street "123 DADE COUNTY RD" must not read as a DAD
    // middle name), which the old match-anywhere fallback did.
    final header = data.split(RegExp(r'[\n\r]')).firstWhere(
        (l) => l.contains('ANSI ') || l.contains('AAMVA'),
        orElse: () => '');
    String? f(String code) {
      final m = RegExp('^$code([^\n\r]*)', multiLine: true).firstMatch(data) ??
          RegExp('$code([^\n\r]*)').firstMatch(header);
      final v = m?.group(1)?.trim();
      return (v == null || v.isEmpty || v.toUpperCase() == 'NONE') ? null : v;
    }

    final number = f('DAQ');
    var last = f('DCS') ?? f('DAB');
    var first = f('DAC') ?? f('DCT');
    var middle = f('DAD');
    // Legacy (AAMVA v1) put the whole name in one comma-separated DAA field:
    // "LAST,FIRST,MIDDLE,SUFFIX".
    if (first == null && last == null) {
      final daa = f('DAA');
      if (daa != null) {
        final p = daa.split(',');
        last = p.isNotEmpty ? p[0] : null;
        first = p.length > 1 ? p[1] : null;
        middle = p.length > 2 ? p[2] : null;
      }
    }
    if (number == null && first == null && last == null) return null;

    final fields = <String, String>{};
    if (number != null) fields['number'] = number;

    final name = [first, middle, last]
        .whereType<String>()
        .map(_title)
        .where((s) => s.isNotEmpty)
        .join(' ');
    if (name.isNotEmpty) fields['name'] = name;

    final dob = _date(f('DBB'));
    if (dob != null) fields['date_of_birth'] = dob;
    final exp = _date(f('DBA'));
    if (exp != null) fields['expires'] = exp;

    // DBC is '1'/'2' (AAMVA) on most, but some jurisdictions write 'M'/'F'.
    final sex = f('DBC')?.toUpperCase();
    if (sex == '1' || sex == 'M') {
      fields['sex'] = 'M';
    } else if (sex == '2' || sex == 'F') {
      fields['sex'] = 'F';
    }

    final cls = f('DCA');
    if (cls != null) fields['class'] = cls;

    final addr = [
      if (f('DAG') != null) _title(f('DAG')!),
      [
        if (f('DAI') != null) _title(f('DAI')!),
        if (f('DAJ') != null) f('DAJ'),
      ].join(' ').trim(),
    ].where((s) => s.isNotEmpty).join(', ');
    if (addr.isNotEmpty) fields['address'] = addr;

    return fields;
  }

  static String _title(String s) => s
      .split(RegExp(r'\s+'))
      .map((w) => w.isEmpty ? w : w[0] + w.substring(1).toLowerCase())
      .join(' ')
      .trim();

  /// AAMVA dates are 8 digits — MMDDCCYY (US) or CCYYMMDD (Canada). Disambiguate
  /// by whether the first two digits are a valid month. → ISO yyyy-mm-dd.
  static String? _date(String? s) {
    if (s == null || !RegExp(r'^\d{8}$').hasMatch(s)) return null;
    final yearFirst = int.parse(s.substring(0, 2)) > 12;
    final y = yearFirst ? s.substring(0, 4) : s.substring(4, 8);
    final mm = yearFirst ? s.substring(4, 6) : s.substring(0, 2);
    final dd = yearFirst ? s.substring(6, 8) : s.substring(2, 4);
    if (int.parse(mm) < 1 || int.parse(mm) > 12) return null;
    return '$y-$mm-$dd';
  }
}
