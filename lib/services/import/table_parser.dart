import '../../data/models/txn.dart';

/// What a spreadsheet column holds.
enum ImportField {
  ignore('Skip this column'),
  date('Date'),
  time('Time'),
  type('Type (income / expense / transfer)'),
  amount('Amount'),
  income('Income amount (credit)'),
  expense('Expense amount (debit)'),
  category('Category'),
  subcategory('Subcategory'),
  account('Account'),
  toAccount('To account (transfers)'),
  note('Note'),
  description('Description');

  const ImportField(this.label);
  final String label;
}

/// Row kinds as they appear in exports. Transfers come as one "out" row and,
/// in some apps, a matching "in" row for the other account.
enum RowKind { income, expense, transferOut, transferIn }

/// One spreadsheet row turned into typed values, before it is matched to
/// accounts and categories. [error] is set when the row can't be imported.
class ParsedRow {
  ParsedRow({
    required this.rowNumber,
    this.date,
    this.kind,
    this.amount,
    this.category = '',
    this.subcategory = '',
    this.account = '',
    this.toAccount = '',
    this.note = '',
    this.description = '',
    this.error,
  });

  /// 1-based, as shown in Excel.
  final int rowNumber;
  final DateTime? date;
  final RowKind? kind;

  /// Paise, always positive.
  final int? amount;
  final String category;
  final String subcategory;
  final String account;

  /// For transfers: the other account. Falls back to [category], which is
  /// where Money Manager style exports put it.
  final String toAccount;
  final String note;
  final String description;
  final String? error;

  bool get ok => error == null;

  String get otherAccount => toAccount.isNotEmpty ? toAccount : category;

  TxnType get txnType => switch (kind!) {
    RowKind.income => TxnType.income,
    RowKind.expense => TxnType.expense,
    _ => TxnType.transfer,
  };
}

/// How to read values the file leaves ambiguous.
class ParseOptions {
  const ParseOptions({this.dayFirst = true, this.defaultKind = RowKind.expense});

  /// 03/04/2026 is 3 April when true (India), 4 March when false.
  final bool dayFirst;

  /// Used when the sheet has no type column and the amount is positive.
  final RowKind defaultKind;
}

/// Reads rows from a spreadsheet already loaded as cells (String, num,
/// DateTime, bool or null). Pure Dart, so it is unit tested.
class TableParser {
  const TableParser();

  /// The first row in the top 15 that has at least two recognisable headers.
  int findHeaderRow(List<List<Object?>> rows) {
    for (var i = 0; i < rows.length && i < 15; i++) {
      final guess = guessColumns(rows[i]);
      final known = guess.values.where((f) => f != ImportField.ignore).length;
      if (known >= 2 && guess.containsValue(ImportField.date)) return i;
    }
    return 0;
  }

  /// Maps each column to a field by its header text. A column headed with
  /// the currency code "INR", as Money Manager writes it, wins over "Amount".
  Map<int, ImportField> guessColumns(List<Object?> header) {
    final names = [for (final h in header) _norm(h)];
    final result = <int, ImportField>{};
    final taken = <ImportField>{};

    void take(int i, ImportField f) {
      if (taken.contains(f) || result.containsKey(i)) return;
      result[i] = f;
      taken.add(f);
    }

    for (var i = 0; i < names.length; i++) {
      if (names[i] == 'inr') take(i, ImportField.amount);
    }
    for (var i = 0; i < names.length; i++) {
      final n = names[i];
      if (n.isEmpty) continue;
      final f = _fieldFor(n);
      if (f != null) take(i, f);
    }
    for (var i = 0; i < names.length; i++) {
      result.putIfAbsent(i, () => ImportField.ignore);
    }
    return result;
  }

  ImportField? _fieldFor(String n) {
    bool has(List<String> words) => words.any(n.contains);
    if (n == 'time') return ImportField.time;
    if (has(['subcategory', 'sub category', 'sub-category'])) return ImportField.subcategory;
    if (has(['to account', 'transfer to', 'destination'])) return ImportField.toAccount;
    if (has(['income/expense', 'income / expense', 'type', 'transaction type', 'kind'])) return ImportField.type;
    if (has(['period', 'date', 'day', 'when'])) return ImportField.date;
    if (has(['category', 'head'])) return ImportField.category;
    if (has(['account', 'wallet', 'bank', 'mode', 'payment method', 'paid via', 'source'])) return ImportField.account;
    final money = has(['amount', 'amt', 'value', '₹']) || n == 'rs' || n == 'rs.';
    if (has(['credit', 'deposit', 'income']) || (money && n.contains('received'))) return ImportField.income;
    if (has(['debit', 'withdrawal', 'expense', 'spent']) || (money && n.contains('paid'))) return ImportField.expense;
    if (money || has(['price', 'total'])) return ImportField.amount;
    if (has(['note', 'memo', 'item', 'title', 'name', 'narration', 'particulars'])) return ImportField.note;
    if (has(['description', 'remark', 'details', 'comment'])) return ImportField.description;
    return null;
  }

  /// Parses every row below [headerRow]. Blank rows are dropped.
  List<ParsedRow> parse(List<List<Object?>> rows, int headerRow, Map<int, ImportField> columns, ParseOptions options) {
    final out = <ParsedRow>[];
    for (var r = headerRow + 1; r < rows.length; r++) {
      final row = rows[r];
      if (row.every((c) => c == null || c.toString().trim().isEmpty)) continue;
      out.add(_parseRow(row, r + 1, columns, options));
    }
    return out;
  }

  ParsedRow _parseRow(List<Object?> row, int rowNumber, Map<int, ImportField> columns, ParseOptions o) {
    Object? cell(ImportField f) {
      for (final e in columns.entries) {
        if (e.value == f && e.key < row.length) return row[e.key];
      }
      return null;
    }

    String text(ImportField f) => _text(cell(f));

    final date = parseDate(cell(ImportField.date), dayFirst: o.dayFirst);
    final time = parseTime(cell(ImportField.time));
    final when = date == null
        ? null
        : (time == null ? date : DateTime(date.year, date.month, date.day, time.$1, time.$2));

    RowKind? kind = parseKind(text(ImportField.type));
    int? amount;
    final rawAmount = parseAmount(cell(ImportField.amount));
    final inAmount = parseAmount(cell(ImportField.income));
    final outAmount = parseAmount(cell(ImportField.expense));
    if (rawAmount != null && rawAmount != 0) {
      amount = rawAmount.abs();
      kind ??= rawAmount < 0 ? RowKind.expense : o.defaultKind;
    } else if (inAmount != null && inAmount != 0) {
      amount = inAmount.abs();
      kind ??= RowKind.income;
    } else if (outAmount != null && outAmount != 0) {
      amount = outAmount.abs();
      kind ??= RowKind.expense;
    }

    String? error;
    if (when == null) {
      error = 'No date it could read';
    } else if (amount == null) {
      error = 'No amount';
    } else if (kind == null) {
      error = 'Type "${text(ImportField.type)}" is not income, expense or transfer';
    }

    return ParsedRow(
      rowNumber: rowNumber,
      date: when,
      kind: kind,
      amount: amount,
      category: text(ImportField.category),
      subcategory: text(ImportField.subcategory),
      account: text(ImportField.account),
      toAccount: text(ImportField.toAccount),
      note: text(ImportField.note),
      description: text(ImportField.description),
      error: error,
    );
  }

  /// Guesses day-first or month-first from the date column: any first part
  /// above 12 means day-first, any second part above 12 means month-first.
  bool? detectDayFirst(List<List<Object?>> rows, int headerRow, int dateColumn) {
    final re = RegExp(r'^\s*(\d{1,2})[/.\-](\d{1,2})[/.\-]\d{2,4}');
    var dayFirst = 0, monthFirst = 0;
    for (var r = headerRow + 1; r < rows.length; r++) {
      if (dateColumn >= rows[r].length) continue;
      final v = rows[r][dateColumn];
      if (v is! String) continue;
      final m = re.firstMatch(v);
      if (m == null) continue;
      if (int.parse(m[1]!) > 12) dayFirst++;
      if (int.parse(m[2]!) > 12) monthFirst++;
    }
    if (dayFirst == 0 && monthFirst == 0) return null;
    return dayFirst >= monthFirst;
  }

  static RowKind? parseKind(String raw) {
    final v = raw.trim().toLowerCase();
    if (v.isEmpty) return null;
    if (v.contains('transfer')) {
      return v.contains('in') && !v.contains('out') ? RowKind.transferIn : RowKind.transferOut;
    }
    if (v.startsWith('inc') || v == 'credit' || v == 'cr' || v == 'received' || v == 'in') return RowKind.income;
    if (v.startsWith('exp') || v == 'debit' || v == 'dr' || v == 'spent' || v == 'out' || v == 'paid') {
      return RowKind.expense;
    }
    return null;
  }

  /// Paise, signed. Accepts numbers and text like "₹1,234.50", "Rs. 90",
  /// "(250)", "-36", "1,250 Dr".
  static int? parseAmount(Object? v) {
    if (v == null) return null;
    if (v is num) return (v * 100).round();
    var s = v.toString().trim();
    if (s.isEmpty) return null;
    var negative = false;
    final lower = s.toLowerCase();
    if (lower.endsWith('dr')) {
      negative = true;
      s = s.substring(0, s.length - 2);
    } else if (lower.endsWith('cr')) {
      s = s.substring(0, s.length - 2);
    }
    if (s.startsWith('(') && s.endsWith(')')) {
      negative = true;
      s = s.substring(1, s.length - 1);
    }
    s = s.replaceAll(RegExp(r'(?:inr|rs\.?|₹|,|\s)', caseSensitive: false), '');
    if (s.startsWith('-')) {
      negative = !negative;
      s = s.substring(1);
    } else if (s.startsWith('+')) {
      s = s.substring(1);
    }
    final d = double.tryParse(s);
    if (d == null) return null;
    final paise = (d * 100).round();
    return negative ? -paise : paise;
  }

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

  /// Accepts DateTime cells, Excel serial numbers (days since 1899-12-30,
  /// with the time as the fraction) and text such as 2026-11-26,
  /// 26/11/2026, 26-Nov-2026 and Nov 26, 2026, with an optional time.
  /// Ambiguous numeric dates follow [dayFirst]. Impossible dates return null.
  static DateTime? parseDate(Object? v, {bool dayFirst = true}) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is num) {
      if (v < 20000 || v > 80000) return null;
      final whole = v.floor();
      final minutes = ((v - whole) * 24 * 60).round();
      return DateTime(1899, 12, 30 + whole).add(Duration(minutes: minutes));
    }
    final s = v.toString().trim();
    if (s.isEmpty) return null;

    final serial = double.tryParse(s);
    if (serial != null) return parseDate(serial, dayFirst: dayFirst);

    (int, int, int)? hms(String? rest) {
      if (rest == null) return null;
      final t = RegExp(r'(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([ap]\.?m\.?)?', caseSensitive: false).firstMatch(rest);
      if (t == null) return null;
      var h = int.parse(t[1]!);
      final ap = t[4]?.toLowerCase();
      if (ap != null && ap.startsWith('p') && h < 12) h += 12;
      if (ap != null && ap.startsWith('a') && h == 12) h = 0;
      return (h, int.parse(t[2]!), int.parse(t[3] ?? '0'));
    }

    DateTime? build(int y, int m, int d, String? rest) {
      if (y < 100) y += 2000;
      if (m < 1 || m > 12 || d < 1 || d > 31) return null;
      final t = hms(rest) ?? (0, 0, 0);
      final date = DateTime(y, m, d, t.$1, t.$2, t.$3);
      return date.month == m ? date : null;
    }

    var m = RegExp(r'^(\d{4})[/.\-](\d{1,2})[/.\-](\d{1,2})(.*)$').firstMatch(s);
    if (m != null) return build(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!), m[4]);

    m = RegExp(r'^(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2,4})(.*)$').firstMatch(s);
    if (m != null) {
      final a = int.parse(m[1]!), b = int.parse(m[2]!), y = int.parse(m[3]!);
      final (d, mo) = a > 12 ? (a, b) : (b > 12 ? (b, a) : (dayFirst ? (a, b) : (b, a)));
      return build(y, mo, d, m[4]);
    }

    m = RegExp(r'^(\d{1,2})[\s\-/]+([A-Za-z]{3,})[\s\-/,]+(\d{2,4})(.*)$').firstMatch(s);
    if (m != null) {
      final mo = _months[m[2]!.substring(0, 3).toLowerCase()];
      if (mo != null) return build(int.parse(m[3]!), mo, int.parse(m[1]!), m[4]);
    }
    m = RegExp(r'^([A-Za-z]{3,})[\s\-/]+(\d{1,2}),?[\s\-/]+(\d{2,4})(.*)$').firstMatch(s);
    if (m != null) {
      final mo = _months[m[1]!.substring(0, 3).toLowerCase()];
      if (mo != null) return build(int.parse(m[3]!), mo, int.parse(m[2]!), m[4]);
    }
    return null;
  }

  /// (hour, minute) from a time cell: text, Excel fraction of a day, or DateTime.
  static (int, int)? parseTime(Object? v) {
    if (v == null) return null;
    if (v is DateTime) return (v.hour, v.minute);
    if (v is num) {
      if (v < 0 || v >= 1) return null;
      final minutes = (v * 24 * 60).round();
      return (minutes ~/ 60 % 24, minutes % 60);
    }
    final t = RegExp(r'(\d{1,2}):(\d{2})\s*([ap]\.?m\.?)?', caseSensitive: false).firstMatch(v.toString());
    if (t == null) return null;
    var h = int.parse(t[1]!);
    final ap = t[3]?.toLowerCase();
    if (ap != null && ap.startsWith('p') && h < 12) h += 12;
    if (ap != null && ap.startsWith('a') && h == 12) h = 0;
    return (h, int.parse(t[2]!));
  }

  static String _text(Object? v) {
    if (v == null) return '';
    if (v is double && v == v.roundToDouble()) return v.toInt().toString();
    return v.toString().trim();
  }

  static String _norm(Object? v) => _text(v).toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
