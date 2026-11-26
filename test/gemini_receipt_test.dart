import 'package:finance_tracker/services/ai/gemini_receipt.dart';
import 'package:finance_tracker/services/receipt_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 26, 10);

  test('maps a full Google Pay answer', () {
    final r = receiptFromGemini({
      'amount': 4000,
      'direction': 'paid',
      'payee': 'FATHIMATHUL MUSHIRIF',
      'payeeUpiId': 'fathima@okaxis',
      'upiRef': '5123 4567 8901',
      'dateTime': '2026-11-25T17:27',
      'status': 'success',
      'app': 'Google Pay',
    }, now: now);
    expect(r.amountPaise, 400000);
    expect(r.direction, ReceiptDirection.paid);
    expect(r.payee, 'Fathimathul Mushirif');
    expect(r.payeeVpa, 'fathima@okaxis');
    expect(r.upiRef, '512345678901');
    expect(r.date, DateTime(2026, 11, 25, 17, 27));
    expect(r.status, ReceiptStatus.success);
    expect(r.app, 'Google Pay');
  });

  test('keeps paise and reads amounts sent as text', () {
    expect(receiptFromGemini({'amount': 249.5}, now: now).amountPaise, 24950);
    expect(receiptFromGemini({'amount': '₹1,299.00'}, now: now).amountPaise, 129900);
  });

  test('drops values that cannot be right', () {
    final r = receiptFromGemini({
      'amount': 0,
      'direction': 'sideways',
      'payee': '  ',
      'payeeUpiId': 'not an id',
      'upiRef': '12',
      'dateTime': '2027-03-01T09:00',
      'status': null,
      'app': 'null',
    }, now: now);
    expect(r.amountPaise, isNull);
    expect(r.direction, ReceiptDirection.unknown);
    expect(r.payee, isNull);
    expect(r.payeeVpa, isNull);
    expect(r.upiRef, isNull);
    expect(r.date, isNull);
    expect(r.status, ReceiptStatus.unknown);
    expect(r.app, isNull);
  });

  test('an empty answer has no amount, so the phone reads the screenshot', () {
    expect(receiptFromGemini({}, now: now).hasAmount, isFalse);
  });
}
