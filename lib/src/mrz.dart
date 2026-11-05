/// Parses the ICAO 9303 **Machine Readable Zone** — the `<<<` lines at the bottom
/// of a passport — into structured, check-digit-validated fields. The MRZ encodes
/// the data exactly, so this is far more reliable than guessing fields from the
/// visual text (and the check digits catch OCR slips). Handles TD3 (passport,
/// 2×44), TD1 (ID card, 3×30), and TD2 (2×36). [parse] returns null when no
/// MRZ is found.
class Mrz {
  /// The first MRZ character — the document type code ('P' passport, 'I'/'A'/'C'
  /// ID card, 'V' visa). Lets a caller distinguish a passport from an ID/green
  /// card when no keyword rule fired.
  final String documentType;
  final String documentNumber;
  final String surname;
  final String givenNames;
  final String nationality;
  final String issuingCountry;
  final String sex; // 'M' | 'F' | '' (unspecified)
  final String? dateOfBirth; // ISO yyyy-mm-dd
  final String? expiryDate; // ISO yyyy-mm-dd

  /// True when the document-number check digit validated — a strong signal the
  /// number (and the line) were read correctly.
  final bool numberValid;

  const Mrz({
    required this.documentType,
    required this.documentNumber,
    required this.surname,
    required this.givenNames,
    required this.nationality,
    required this.issuingCountry,
    required this.sex,
    required this.dateOfBirth,
    required this.expiryDate,
    required this.numberValid,
  });

  /// "Given Surname" ("Anna Maria Eriksson"). Names are stored title-cased.
  String get fullName =>
      [givenNames, surname].where((s) => s.isNotEmpty).join(' ').trim();

  /// Parse a passport (TD3, 2×44), ID card (TD1, 3×30), or visa/old ID (TD2,
  /// 2×36) MRZ out of [text]. [nowYear] resolves the 2-digit-year century.
  static Mrz? parse(String text, {int? nowYear}) {
    // Candidate MRZ lines: uppercased, stripped to the MRZ alphabet, must hold a
    // filler '<' (every real MRZ line does). OCR routinely splits a line's
    // trailing '<' filler onto a line of its own (seen from Vision on TD1
    // cards) — re-join a mostly-'<' fragment onto the MRZ-ish line before it,
    // so the length gates below see the line the card actually printed.
    // '<' confusables first: ML Kit reads a '<<' pair as a guillemet '«' and a
    // lone '<' as '(' — deleting them (instead of expanding) shortens the line
    // past the format gates.
    final stripped = [
      for (final raw in text.split('\n'))
        raw
            .toUpperCase()
            .replaceAll('«', '<<')
            .replaceAll('»', '<<')
            .replaceAll(RegExp(r'[‹›(\[{]'), '<')
            .replaceAll(RegExp(r'[^A-Z0-9<]'), ''),
    ].where((l) => l.isNotEmpty).toList();
    final merged = <String>[];
    for (final l in stripped) {
      final fillerFragment = merged.isNotEmpty &&
          l.length <= 12 &&
          '<'.allMatches(l).length * 2 >= l.length &&
          merged.last.length >= 20 &&
          merged.last.length < 44 &&
          merged.last.contains('<');
      if (fillerFragment) {
        merged[merged.length - 1] = merged.last + l;
      } else {
        merged.add(l);
      }
    }
    final lines =
        merged.where((l) => l.length >= 24 && l.contains('<')).toList();

    for (var i = 0; i < lines.length; i++) {
      // TD1: three ~30-char lines.
      if (i + 2 < lines.length &&
          _fits(lines[i], 30) &&
          _fits(lines[i + 1], 30) &&
          _fits(lines[i + 2], 30)) {
        final m = _td1(_pad(lines[i], 30), _pad(lines[i + 1], 30),
            _pad(lines[i + 2], 30), nowYear);
        if (m != null) return m;
      }
      if (i + 1 < lines.length) {
        // TD3: two ~44-char lines (tried before TD2 — a clean TD3 pair can
        // also pass TD2's window).
        if (_fits(lines[i], 44) && _fits(lines[i + 1], 44)) {
          final m =
              _td3(_pad(lines[i], 44), _pad(lines[i + 1], 44), nowYear);
          if (m != null) return m;
        }
        // TD2: two ~36-char lines.
        if (_fits(lines[i], 36) && _fits(lines[i + 1], 36)) {
          final m =
              _td2(_pad(lines[i], 36), _pad(lines[i + 1], 36), nowYear);
          if (m != null) return m;
        }
      }
    }
    return null;
  }

  /// OCR length tolerance around a format's line length [n]: filler runs read
  /// SHORT (dropped '<'s — data rides at the line's front, so right-padding
  /// restores it) or LONG (doubled '<'s — truncation only sheds filler). Wide
  /// on purpose: the check digits + date validation are what reject a
  /// non-MRZ line, not the length window.
  static bool _fits(String l, int n) => l.length >= n - 6 && l.length <= n + 8;
  static String _pad(String l, int n) =>
      l.length >= n ? l.substring(0, n) : l.padRight(n, '<');

  // ---- Per-format field layouts (ICAO 9303) ----

  static Mrz? _td3(String l1, String l2, int? nowYear) {
    if (l1[0] != 'P') return null;
    return _build(
      nowYear: nowYear,
      docType: l1[0],
      country: l1.substring(2, 5),
      nameField: l1.substring(5),
      number: l2.substring(0, 9),
      numberCheck: l2[9],
      nationality: l2.substring(10, 13),
      dob: l2.substring(13, 19),
      dobCheck: l2[19],
      sex: l2[20],
      expiry: l2.substring(21, 27),
      expiryCheck: l2[27],
    );
  }

  static Mrz? _td2(String l1, String l2, int? nowYear) {
    if (!_isAlpha(l1[0])) return null;
    return _build(
      nowYear: nowYear,
      docType: l1[0],
      country: l1.substring(2, 5),
      nameField: l1.substring(5, 36),
      number: l2.substring(0, 9),
      numberCheck: l2[9],
      nationality: l2.substring(10, 13),
      dob: l2.substring(13, 19),
      dobCheck: l2[19],
      sex: l2[20],
      expiry: l2.substring(21, 27),
      expiryCheck: l2[27],
    );
  }

  static Mrz? _td1(String l1, String l2, String l3, int? nowYear) {
    if (!_isAlpha(l1[0])) return null;
    return _build(
      nowYear: nowYear,
      docType: l1[0],
      country: l1.substring(2, 5),
      nameField: l3.substring(0, 30),
      number: l1.substring(5, 14),
      numberCheck: l1[14],
      nationality: l2.substring(15, 18),
      dob: l2.substring(0, 6),
      dobCheck: l2[6],
      sex: l2[7],
      expiry: l2.substring(8, 14),
      expiryCheck: l2[14],
    );
  }

  static bool _isAlpha(String c) => RegExp(r'^[A-Z]$').hasMatch(c);

  /// Build an [Mrz] from the common raw fields; null if the dates don't parse
  /// (a strong "this isn't really an MRZ" signal that guards false positives).
  /// A date whose OWN check digit fails, or whose day-of-month is impossible, is
  /// dropped (returned absent) rather than emitted — MRZ fields override the LLM
  /// as "verified", so a wrong-but-plausible date must never pass silently.
  static Mrz? _build({
    required int? nowYear,
    required String docType,
    required String country,
    required String nameField,
    required String number,
    required String numberCheck,
    required String nationality,
    required String dob,
    required String dobCheck,
    required String sex,
    required String expiry,
    required String expiryCheck,
  }) {
    final dobIso = _check(dob, dobCheck)
        ? _isoDate(dob, isBirth: true, nowYear: nowYear)
        : null;
    final expIso = _check(expiry, expiryCheck)
        ? _isoDate(expiry, isBirth: false, nowYear: nowYear)
        : null;
    if (dobIso == null && expIso == null) return null;
    final parts = nameField.split('<<');
    return Mrz(
      documentType: docType,
      documentNumber: number.replaceAll('<', ''),
      surname: _name(parts.isNotEmpty ? parts[0] : ''),
      givenNames: _name(parts.length > 1 ? parts[1] : ''),
      nationality: _alphaFix(nationality.replaceAll('<', '')),
      issuingCountry: _alphaFix(country.replaceAll('<', '')),
      sex: sex == '<' ? '' : sex,
      dateOfBirth: dobIso,
      expiryDate: expIso,
      numberValid: _check(number, numberCheck),
    );
  }

  /// Country/nationality codes are letters-only — undo the classic OCR
  /// digit-for-letter swaps ('UT0' → 'UTO') the check digits can't catch
  /// (these fields aren't covered by one).
  static String _alphaFix(String s) => s
      .replaceAll('0', 'O')
      .replaceAll('1', 'I')
      .replaceAll('2', 'Z')
      .replaceAll('5', 'S')
      .replaceAll('8', 'B');

  static String _name(String s) {
    final cleaned =
        s.replaceAll('<', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return [
      for (final w in cleaned.split(' '))
        if (w.isNotEmpty) w[0] + w.substring(1).toLowerCase(),
    ].join(' ');
  }

  /// YYMMDD → ISO yyyy-mm-dd. Birth years pivot on [nowYear] (a 2-digit year past
  /// "now" is last century); expiry is always 20YY. Rejects an impossible month
  /// or day-of-month (per-month, leap-aware) so an OCR-mangled date that happens
  /// to carry a matching check digit still can't produce a bogus value.
  static String? _isoDate(String yymmdd, {required bool isBirth, int? nowYear}) {
    if (!RegExp(r'^\d{6}$').hasMatch(yymmdd)) return null;
    final yy = int.parse(yymmdd.substring(0, 2));
    final mm = int.parse(yymmdd.substring(2, 4));
    final dd = int.parse(yymmdd.substring(4, 6));
    if (mm < 1 || mm > 12) return null;
    final pivot = (nowYear ?? DateTime.now().year) % 100;
    final year = isBirth ? (yy > pivot ? 1900 + yy : 2000 + yy) : 2000 + yy;
    if (dd < 1 || dd > _daysInMonth(year, mm)) return null;
    return '$year-${_pad2(mm)}-${_pad2(dd)}';
  }

  static String _pad2(int n) => n.toString().padLeft(2, '0');

  static int _daysInMonth(int year, int month) {
    const days = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    final leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
    return (month == 2 && leap) ? 29 : days[month - 1];
  }

  // ICAO check digit: weights 7,3,1; '<'=0, digit=value, A..Z=10..35.
  static bool _check(String field, String checkChar) {
    if (!RegExp(r'^\d$').hasMatch(checkChar)) return false;
    const weights = [7, 3, 1];
    var sum = 0;
    for (var i = 0; i < field.length; i++) {
      final c = field.codeUnitAt(i);
      final v = c == 0x3C // '<'
          ? 0
          : (c >= 0x30 && c <= 0x39) // 0-9
              ? c - 0x30
              : (c >= 0x41 && c <= 0x5A) // A-Z
                  ? c - 0x41 + 10
                  : 0;
      sum += v * weights[i % 3];
    }
    return sum % 10 == int.parse(checkChar);
  }
}
