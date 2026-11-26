/// Reads the text that OCR pulls out of a UPI payment screenshot (Google Pay,
/// PhonePe, Paytm, BHIM, bank apps) and extracts what a transaction needs.
///
/// Pure Dart with no plugin calls, so it is unit tested against sample text.
/// OCR is noisy (₹ is often read as "Z", "F" or "%"), so every result is a
/// suggestion: the app always shows a prefilled form for the user to confirm.
library;

/// Whether the screenshot shows money paid or received.
enum ReceiptDirection { paid, received, unknown }

/// The payment status the screenshot shows.
enum ReceiptStatus { success, failed, pending, unknown }

/// What could be read from a screenshot. Every field may be missing.
class ReceiptParseResult {
  const ReceiptParseResult({
    this.amountPaise,
    this.payee,
    this.payeeVpa,
    this.date,
    this.upiRef,
    this.direction = ReceiptDirection.unknown,
    this.status = ReceiptStatus.unknown,
    this.app,
    required this.rawText,
  });

  final int? amountPaise;
  final String? payee;

  /// UPI id such as name@okaxis, when visible.
  final String? payeeVpa;
  final DateTime? date;

  /// UPI reference / UTR. Used to detect the same payment being added twice.
  final String? upiRef;
  final ReceiptDirection direction;
  final ReceiptStatus status;

  /// Google Pay, PhonePe, Paytm and so on, when recognisable.
  final String? app;
  final String rawText;

  bool get hasAmount => amountPaise != null;
}

/// Turns OCR text into a [ReceiptParseResult].
class ReceiptParser {
  const ReceiptParser();

  static const _months = {
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  };

  ReceiptParseResult parse(String text) {
    final lines = text.split(RegExp(r'\r?\n')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    return ReceiptParseResult(
      amountPaise: _amount(lines),
      payee: _payee(lines),
      payeeVpa: _vpa(lines),
      date: _date(text),
      upiRef: _upiRef(lines),
      direction: _direction(text),
      status: _status(text),
      app: _app(text),
      rawText: text,
    );
  }

  static final _currencyAmount = RegExp(
    r'(?:₹|rs\.?|inr)\s*([0-9]{1,3}(?:,[0-9]{2,3})+(?:\.[0-9]{1,2})?|[0-9]+(?:\.[0-9]{1,2})?)',
    caseSensitive: false,
  );

  /// A line holding only an amount, allowing a misread ₹ in front.
  static final _bareAmountLine = RegExp(
    r'^[₹zZF%*=Rr]?\s?([0-9]{1,3}(?:,[0-9]{2,3})+(?:\.[0-9]{1,2})?|[0-9]{1,7}(?:\.[0-9]{1,2})?)$',
  );

  static final _amountLabel = RegExp(r'\b(amount|total|paid|debited|credited|sent)\b', caseSensitive: false);

  /// The most likely paid amount. A currency-marked figure beats a lone
  /// number, and a lone number counts only with a label or a comma.
  int? _amount(List<String> lines) {
    int? best;
    var bestScore = -1;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (_looksLikeNonAmount(line)) continue;
      final labelled =
          _amountLabel.hasMatch(line) || (i > 0 && _amountLabel.hasMatch(lines[i - 1]) && lines[i - 1].length < 30);

      for (final m in _currencyAmount.allMatches(line)) {
        final v = _toPaise(m.group(1)!);
        if (v == null) continue;
        final score = 3 + (labelled ? 1 : 0);
        if (score > bestScore) {
          best = v;
          bestScore = score;
        }
      }
      final bare = _bareAmountLine.firstMatch(line);
      if (bare != null) {
        final digits = bare.group(1)!;
        final v = _toPaise(digits);
        final hasSymbol = line.length > digits.length;
        if (v != null && (hasSymbol || labelled || digits.contains(','))) {
          final score = (hasSymbol ? 2 : 1) + (labelled ? 1 : 0);
          if (score > bestScore) {
            best = v;
            bestScore = score;
          }
        }
      }
    }
    return best;
  }

  /// References, times, years and masked account numbers.
  bool _looksLikeNonAmount(String line) {
    final l = line.toLowerCase();
    return l.contains('transaction id') ||
        l.contains('utr') ||
        l.contains('ref') ||
        RegExp(r'\b\d{1,2}:\d{2}\b').hasMatch(l) ||
        RegExp(r'\b(19|20)\d{2}\b').hasMatch(l) && !l.contains('₹') && !l.contains('rs') ||
        RegExp(r'x{2,}\d{2,4}|\*{2,}\d{2,4}').hasMatch(l);
  }

  int? _toPaise(String s) {
    final clean = s.replaceAll(',', '');
    final value = double.tryParse(clean);
    if (value == null || value <= 0 || value > 10000000) return null;
    return (value * 100).round();
  }

  static final _payeeInline = RegExp(
    r'^(?:paid to|sent to|payment to|transferred to|to|received from|from)\s*[:\-]?\s+(.{2,60})$',
    caseSensitive: false,
  );
  static final _payeeLabelOnly = RegExp(
    r'^(?:paid to|sent to|payment to|transferred to|received from|to|from)\s*:?$',
    caseSensitive: false,
  );

  String? _payee(List<String> lines) {
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final inline = _payeeInline.firstMatch(line);
      if (inline != null) {
        final name = _cleanName(inline.group(1)!);
        if (name != null) return name;
      }
      if (_payeeLabelOnly.hasMatch(line) && i + 1 < lines.length) {
        final name = _cleanName(lines[i + 1]);
        if (name != null) return name;
      }
    }
    return null;
  }

  /// Strips a trailing UPI id or bank detail and rejects non-names.
  String? _cleanName(String raw) {
    var name = raw.trim();
    name = name.replaceAll(RegExp(r'\s*[\w.\-]+@[\w]+.*$'), '');
    name = name.replaceAll(RegExp(r'\s*(?:x{2,}|\*{2,})\d+.*$', caseSensitive: false), '');
    name = name.replaceAll(RegExp(r'[^\w\s.&\-]'), '').trim();
    if (name.length < 2) return null;
    final lower = name.toLowerCase();
    const notNames = ['your account', 'you', 'bank', 'self', 'banking name'];
    if (notNames.contains(lower)) return null;
    if (RegExp(r'^\d+$').hasMatch(name)) return null;
    if (RegExp(r'(19|20)\d{2}').hasMatch(name)) return null;
    return name;
  }

  static final _vpaPattern = RegExp(r'\b([a-zA-Z0-9.\-_]{2,})@([a-zA-Z]{2,})\b');

  String? _vpa(List<String> lines) {
    for (final l in lines) {
      final m = _vpaPattern.firstMatch(l);
      if (m != null && !l.toLowerCase().contains('mail')) return m.group(0);
    }
    return null;
  }

  static final _refLabel = RegExp(
    r'(upi\s*(?:transaction|txn|ref(?:erence)?)\s*(?:id|no\.?|number)?|utr\s*(?:no\.?|number)?|upi\s*ref\.?\s*(?:no\.?)?|ref(?:erence)?\s*(?:no\.?|number|id))',
    caseSensitive: false,
  );
  static final _txnIdLabel = RegExp(r'transaction\s*id', caseSensitive: false);
  static final _twelveDigits = RegExp(r'\b(\d{12})\b');
  static final _alnumId = RegExp(r'\b([A-Z0-9]{10,35})\b');

  /// Tries, in order: a value after a UPI ref or UTR label (same or next
  /// line), any stand-alone 12-digit number, then the app's own
  /// transaction id.
  String? _upiRef(List<String> lines) {
    for (var i = 0; i < lines.length; i++) {
      final m = _refLabel.firstMatch(lines[i]);
      if (m == null) continue;
      final rest = lines[i].substring(m.end);
      final candidates = [rest, if (i + 1 < lines.length) lines[i + 1]];
      for (final c in candidates) {
        final digits = _twelveDigits.firstMatch(c.replaceAll(' ', ''));
        if (digits != null) return digits.group(1);
        final id = _alnumId.firstMatch(c.replaceAll(' ', ''));
        if (id != null && RegExp(r'\d').hasMatch(id.group(1)!)) return id.group(1);
      }
    }
    for (final l in lines) {
      final compact = l.replaceAll(' ', '');
      final m = RegExp(r'^\d{12}$').firstMatch(compact);
      if (m != null) return compact;
    }
    for (var i = 0; i < lines.length; i++) {
      final m = _txnIdLabel.firstMatch(lines[i]);
      if (m == null) continue;
      final rest = lines[i].substring(m.end);
      final candidates = [rest, if (i + 1 < lines.length) lines[i + 1]];
      for (final c in candidates) {
        final id = _alnumId.firstMatch(c.replaceAll(' ', ''));
        if (id != null && RegExp(r'\d').hasMatch(id.group(1)!)) return id.group(1);
      }
    }
    return null;
  }

  /// Numeric dates are read day first, as Indian receipts write them.
  DateTime? _date(String text) {
    final t = text.replaceAll('\n', ' ');
    final time =
        RegExp(r'(\d{1,2})[:.](\d{2})\s*([ap]\.?m\.?)', caseSensitive: false).firstMatch(t) ??
        RegExp(r'\b(\d{1,2}):(\d{2})\b').firstMatch(t);

    DateTime? day;
    final named = RegExp(
      r'\b(\d{1,2})(?:st|nd|rd|th)?\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?,?\s+(\d{4})',
      caseSensitive: false,
    ).firstMatch(t);
    final namedMonthFirst = RegExp(
      r'\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+(\d{1,2}),?\s+(\d{4})',
      caseSensitive: false,
    ).firstMatch(t);
    final numeric = RegExp(r'\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})\b').firstMatch(t);

    if (named != null) {
      day = _safeDate(int.parse(named.group(3)!), _months[named.group(2)!.toLowerCase()]!, int.parse(named.group(1)!));
    } else if (namedMonthFirst != null) {
      day = _safeDate(
        int.parse(namedMonthFirst.group(3)!),
        _months[namedMonthFirst.group(1)!.toLowerCase()]!,
        int.parse(namedMonthFirst.group(2)!),
      );
    } else if (numeric != null) {
      var year = int.parse(numeric.group(3)!);
      if (year < 100) year += 2000;
      day = _safeDate(year, int.parse(numeric.group(2)!), int.parse(numeric.group(1)!));
    }
    if (day == null) return null;

    if (time != null) {
      var hour = int.parse(time.group(1)!);
      final minute = int.parse(time.group(2)!);
      final meridian = time.groupCount >= 3 ? time.group(3)?.toLowerCase().replaceAll('.', '') : null;
      if (meridian == 'pm' && hour < 12) hour += 12;
      if (meridian == 'am' && hour == 12) hour = 0;
      if (hour < 24 && minute < 60) {
        return DateTime(day.year, day.month, day.day, hour, minute);
      }
    }
    return day;
  }

  DateTime? _safeDate(int year, int month, int day) {
    if (month < 1 || month > 12 || day < 1 || day > 31 || year < 2000 || year > 2100) return null;
    final d = DateTime(year, month, day);
    return d.month == month ? d : null;
  }

  ReceiptDirection _direction(String text) {
    final t = text.toLowerCase();
    if (RegExp(r'received from|credited|money received|you received').hasMatch(t)) {
      return ReceiptDirection.received;
    }
    if (RegExp(
      r'paid to|sent to|payment to|debited|you paid|paid successfully|payment successful|transferred to|\bto\b',
    ).hasMatch(t)) {
      return ReceiptDirection.paid;
    }
    return ReceiptDirection.unknown;
  }

  ReceiptStatus _status(String text) {
    final t = text.toLowerCase();
    if (RegExp(r'\b(failed|declined|unsuccessful)\b').hasMatch(t)) return ReceiptStatus.failed;
    if (RegExp(r'\b(pending|processing)\b').hasMatch(t)) return ReceiptStatus.pending;
    if (RegExp(r'\b(completed|successful|success|paid|sent|received)\b').hasMatch(t)) {
      return ReceiptStatus.success;
    }
    return ReceiptStatus.unknown;
  }

  String? _app(String text) {
    final t = text.toLowerCase();
    if (t.contains('phonepe')) return 'PhonePe';
    if (t.contains('paytm')) return 'Paytm';
    if (t.contains('google pay') || t.contains('gpay') || t.contains('g pay')) return 'Google Pay';
    if (t.contains('bhim')) return 'BHIM';
    if (t.contains('cred')) return 'CRED';
    if (t.contains('amazon pay')) return 'Amazon Pay';
    return null;
  }
}
