import 'dart:convert';

import '../receipt_parser.dart';

/// Every payment in Gemini's answer that has a readable amount, top to
/// bottom as the screenshot shows them.
List<ReceiptParseResult> receiptsFromGemini(Map<String, Object?> json, {required DateTime now}) {
  final payments = json['payments'];
  if (payments is! List) return const [];
  return [
    for (final p in payments)
      if (p is Map<String, Object?>) receiptFromGemini(p, now: now),
  ].where((r) => r.hasAmount).toList();
}

/// Turns one payment from Gemini's JSON answer into a [ReceiptParseResult].
///
/// Gemini is told to leave out what it can't see, but each field is still
/// checked here, so an odd answer becomes a missing field rather than a
/// wrong one. [now] stops a misread year from dating an entry in the future.
ReceiptParseResult receiptFromGemini(Map<String, Object?> json, {required DateTime now}) {
  return ReceiptParseResult(
    amountPaise: _amount(json['amount']),
    payee: _name(json['payee']),
    payeeVpa: _match(json['payeeUpiId'], RegExp(r'^[a-zA-Z0-9.\-_]{2,}@[a-zA-Z]{2,}$')),
    date: _date(json['dateTime'], now),
    upiRef: _upiRef(json['upiRef']),
    direction: switch (json['direction']) {
      'paid' => ReceiptDirection.paid,
      'received' => ReceiptDirection.received,
      _ => ReceiptDirection.unknown,
    },
    status: switch (json['status']) {
      'success' => ReceiptStatus.success,
      'failed' => ReceiptStatus.failed,
      'pending' => ReceiptStatus.pending,
      _ => ReceiptStatus.unknown,
    },
    app: _text(json['app']),
    hasTime: _text(json['dateTime'])?.contains('T') ?? false,
    rawText: jsonEncode(json),
  );
}

int? _amount(Object? value) {
  final rupees = switch (value) {
    num n => n.toDouble(),
    String s => double.tryParse(s.replaceAll(RegExp(r'[^0-9.]'), '')),
    _ => null,
  };
  if (rupees == null || rupees <= 0 || rupees >= 10000000) return null;
  return (rupees * 100).round();
}

String? _text(Object? value) {
  if (value is! String) return null;
  final s = value.trim();
  return s.isEmpty || s.toLowerCase() == 'null' ? null : s;
}

String? _name(Object? value) {
  final s = _text(value);
  return s == null ? null : ReceiptParser.titleCase(s.replaceAll(RegExp(r'\s+'), ' '));
}

String? _match(Object? value, RegExp pattern) {
  final s = _text(value);
  return s != null && pattern.hasMatch(s) ? s : null;
}

String? _upiRef(Object? value) {
  final s = _text(value)?.replaceAll(RegExp(r'\s'), '');
  return s != null && RegExp(r'^[A-Za-z0-9]{8,35}$').hasMatch(s) ? s : null;
}

DateTime? _date(Object? value, DateTime now) {
  final s = _text(value);
  final d = s == null ? null : DateTime.tryParse(s);
  if (d == null || d.year < 2000 || d.isAfter(now.add(const Duration(days: 1)))) return null;
  return d.isUtc ? d.toLocal() : d;
}
