import 'package:finance_tracker/services/capture/notification_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const p = NotificationParser();

  void expectPayment(ParsedPayment? r, PaymentDirection dir, int paise, {String? to, String? ref, String? account}) {
    expect(r, isNotNull);
    expect(r!.direction, dir);
    expect(r.amount, paise);
    if (to != null) expect(r.counterparty, to);
    if (ref != null) expect(r.upiRef, ref);
    if (account != null) expect(r.accountHint, account);
  }

  group('UPI apps', () {
    test('Google Pay paid', () {
      expectPayment(
        p.parse('₹450 paid to Rahul Kumar', 'Paid using HDFC Bank 1234'),
        PaymentDirection.debit,
        45000,
        to: 'Rahul Kumar',
      );
    });
    test('Google Pay received', () {
      expectPayment(p.parse('Arif Khan', 'Paid you ₹2,000'), PaymentDirection.credit, 200000, to: 'Arif Khan');
    });
    test('PhonePe sent and received', () {
      expectPayment(
        p.parse('Payment successful', 'Paid ₹250 to Swiggy via UPI'),
        PaymentDirection.debit,
        25000,
        to: 'Swiggy',
      );
      expectPayment(
        p.parse('Money received', 'Received ₹1,500.50 from Fatima S in your bank account'),
        PaymentDirection.credit,
        150050,
        to: 'Fatima S',
      );
    });
    test('Paytm', () {
      expectPayment(
        p.parse('Paid Successfully', 'Rs.120 paid to Chai Point. UPI Ref No 533412987654'),
        PaymentDirection.debit,
        12000,
        to: 'Chai Point',
        ref: '533412987654',
      );
    });
  });

  group('bank SMS', () {
    test('UPI debit names the account and reference', () {
      expectPayment(
        p.parse(
          'AX-HDFCBK',
          'Rs.500.00 debited from A/c XX1234 on 26-11-26 to VPA rahul@okicici (UPI Ref No 533412987654). Not you? Call 1800',
          sms: true,
        ),
        PaymentDirection.debit,
        50000,
        to: 'rahul@okicici',
        ref: '533412987654',
        account: '1234',
      );
    });
    test('"debited ... and credited to" is a debit', () {
      expectPayment(
        p.parse(
          'VM-SBIUPI',
          'Dear UPI user A/C X5678 debited by 90.0 on date 26Nov26 trf to ZOMATO Refno 533498765432. If not u? call',
          sms: true,
        ),
        PaymentDirection.debit,
        9000,
        to: 'ZOMATO',
        ref: '533498765432',
        account: '5678',
      );
    });
    test('salary credit', () {
      expectPayment(
        p.parse(
          'JM-ICICIB',
          'Your A/c XX9012 is credited with INR 50,000.00 on 01-Nov-26 by NEFT from ACME PVT LTD. Ref 123456789012',
          sms: true,
        ),
        PaymentDirection.credit,
        5000000,
        account: '9012',
        to: 'ACME PVT LTD',
      );
    });
    test('Canara "Dr." UPI debit', () {
      expectPayment(
        p.parse(
          'AD-CANBNK-S',
          'Dear Customer, Acct XXXX0227 Dr. INR 1.00 on 27/11/26 to HAMNA NOOF; UPI: 633112345678. '
              'Not you? Call 18001030 or SMS BLOCK -Canara Bank',
          sms: true,
        ),
        PaymentDirection.debit,
        100,
        to: 'HAMNA NOOF',
        ref: '633112345678',
        account: '0227',
      );
    });
    test('Canara "Cr." UPI credit', () {
      expectPayment(
        p.parse(
          'AD-CANBNK-S',
          'Dear Customer, Acct XXXX0227 Cr. INR 500.00 on 27/11/26 from ARIF K; UPI: 633112345678',
          sms: true,
        ),
        PaymentDirection.credit,
        50000,
        to: 'ARIF K',
        account: '0227',
      );
    });
    test('Axis "Debit INR"', () {
      expectPayment(
        p.parse('VM-AXISBK', 'Debit INR 250.00 A/c no. XX4455 27-11-26 UPI/P2M/633112345678/SWIGGY', sms: true),
        PaymentDirection.debit,
        25000,
        account: '4455',
      );
    });
    test('card spend', () {
      expectPayment(
        p.parse(
          'AD-HDFCBK',
          'Rs.1,299 spent on HDFC Bank Card x4321 at AMAZON on 2026-11-26:13:05:11. Not you? SMS BLOCK',
          sms: true,
        ),
        PaymentDirection.debit,
        129900,
        to: 'AMAZON',
        account: '4321',
      );
    });
  });

  group('ignored', () {
    for (final (title, text, sms) in [
      ('AX-HDFCBK', '123456 is the OTP for your txn of Rs 2,000 at AMAZON. Do not share.', true),
      ('Rahul Kumar', 'Rahul Kumar requested ₹500 from you', false),
      ('Bill reminder', 'Your electricity bill of ₹1,240 is due on 30 Nov', false),
      ('Payment failed', '₹300 to Swiggy failed. Money will be refunded if debited', false),
      ('Cashback', 'You won ₹25 cashback!', false),
      ('AX-SBIINB', 'Avl Bal is Rs 12,340.00 in A/c X1234', true),
      ('Ayesha', 'can you send me rs 500 for the cab', true),
      ('Ayesha', 'I paid rs 500 for the cab, will settle later', true),
      ('Autopay', 'Rs 799 will be debited on 1 Dec for Netflix', false),
    ]) {
      test(text, () => expect(p.parse(title, text, sms: sms), isNull));
    }
  });
}
