import 'package:finance_tracker/services/receipt_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = ReceiptParser();

  test('Google Pay paid screen', () {
    const text = '''
To Rahul Traders
rahultraders@okaxis
₹1,250
Completed
17 Nov 2026, 10:47 pm
UPI transaction ID
534112345678
Google transaction ID
CICAgOCxyz12345
Paid with
State Bank of India 1234
''';
    final r = parser.parse(text);
    expect(r.amountPaise, 125000);
    expect(r.payee, 'Rahul Traders');
    expect(r.payeeVpa, 'rahultraders@okaxis');
    expect(r.upiRef, '534112345678');
    expect(r.date, DateTime(2026, 11, 17, 22, 47));
    expect(r.direction, ReceiptDirection.paid);
    expect(r.status, ReceiptStatus.success);
  });

  test('Google Pay amount with rupee symbol misread as Z', () {
    const text = '''
To Hotel Paragon
Z90
Completed
3 Nov 2026, 1:15 pm
UPI transaction ID
612398765432
''';
    final r = parser.parse(text);
    expect(r.amountPaise, 9000);
    expect(r.payee, 'Hotel Paragon');
  });

  test('PhonePe transaction successful screen', () {
    const text = '''
Transaction Successful
10:47 pm on 05 Nov 2026
Paid to
AMEEN K
9876543210@ybl
₹ 500
Transfer Details
Transaction ID
T2611051047123456789012
Debited from
XXXXXXXX4321
₹500
UTR: 431298765401
''';
    final r = parser.parse(text);
    expect(r.amountPaise, 50000);
    expect(r.payee, 'AMEEN K');
    expect(r.upiRef, '431298765401');
    expect(r.date, DateTime(2026, 11, 5, 22, 47));
    expect(r.direction, ReceiptDirection.paid);
  });

  test('Paytm with Rs and decimals', () {
    const text = '''
Paytm
Paid Successfully to
Kerala Bus Co
Rs.26.50
UPI Ref No: 789012345678
16 Nov 2026, 08:05 AM
''';
    final r = parser.parse(text);
    expect(r.amountPaise, 2650);
    expect(r.upiRef, '789012345678');
    expect(r.date, DateTime(2026, 11, 16, 8, 5));
    expect(r.app, 'Paytm');
  });

  test('received money is detected as income', () {
    const text = '''
Received from Cybro Payroll
₹32,185.00
Completed
1 Nov 2026
UPI transaction ID 600011112222
''';
    final r = parser.parse(text);
    expect(r.direction, ReceiptDirection.received);
    expect(r.amountPaise, 3218500);
    expect(r.payee, 'Cybro Payroll');
  });

  test('failed payment is flagged', () {
    final r = parser.parse('To Someone\n₹200\nPayment failed\n2 Nov 2026');
    expect(r.status, ReceiptStatus.failed);
  });

  test('numeric dates are read day first', () {
    final r = parser.parse('Paid to Shop\n₹75\n04/11/2026 09:30');
    expect(r.date, DateTime(2026, 11, 4, 9, 30));
  });

  test('no amount when nothing looks like money', () {
    final r = parser.parse('Some random screenshot\nhello world');
    expect(r.amountPaise, isNull);
  });
}
