import 'package:intl/intl.dart';

/// Money is stored everywhere as integer paise (1 rupee = 100 paise) so that
/// sums never pick up floating point drift.
typedef Paise = int;

final NumberFormat _inrWithDecimals = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
final NumberFormat _inrWhole = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final NumberFormat _plainWithDecimals = NumberFormat('#,##,##0.00', 'en_IN');
final NumberFormat _plainWhole = NumberFormat('#,##,##0', 'en_IN');

/// Formats paise as Indian rupees with lakh grouping, e.g. ₹2,42,059.
/// Decimals are shown only when the amount has a paise part.
String formatMoney(Paise paise, {bool symbol = true, bool signed = false}) {
  final negative = paise < 0;
  final abs = paise.abs();
  final whole = abs % 100 == 0;
  final value = abs / 100;
  final String body;
  if (symbol) {
    body = whole ? _inrWhole.format(value) : _inrWithDecimals.format(value);
  } else {
    body = whole ? _plainWhole.format(value) : _plainWithDecimals.format(value);
  }
  if (negative) return '-$body';
  if (signed && paise > 0) return '+$body';
  return body;
}

/// Parses user input like "1,250.50", "₹90", "90" into paise.
/// Returns null when the text holds no valid positive amount.
Paise? parseMoney(String input) {
  final cleaned = input.replaceAll(RegExp(r'[₹,\s]'), '').replaceAll(RegExp(r'^(Rs\.?|INR)', caseSensitive: false), '');
  if (cleaned.isEmpty) return null;
  final match = RegExp(r'^\d+(\.\d{1,2})?$').firstMatch(cleaned);
  if (match == null) return null;
  final parts = cleaned.split('.');
  final rupees = int.parse(parts[0]);
  var paise = 0;
  if (parts.length == 2) {
    paise = int.parse(parts[1].padRight(2, '0'));
  }
  final total = rupees * 100 + paise;
  return total > 0 ? total : null;
}

/// Converts paise to an editable string without grouping, e.g. 125050 -> "1250.50".
String paiseToInput(Paise paise) {
  final rupees = paise ~/ 100;
  final rest = paise % 100;
  return rest == 0 ? '$rupees' : '$rupees.${rest.toString().padLeft(2, '0')}';
}
