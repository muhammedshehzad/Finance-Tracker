import 'package:finance_tracker/data/models/account.dart';
import 'package:finance_tracker/data/models/category.dart';
import 'package:finance_tracker/data/models/txn.dart';
import 'package:finance_tracker/services/voice_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const categories = [
    Category(id: 1, name: 'Food', kind: CategoryKind.expense, keywords: ['lunch', 'tea', 'breakfast', 'snacks']),
    Category(id: 2, name: 'Transport', kind: CategoryKind.expense, keywords: ['bus', 'auto', 'petrol']),
    Category(id: 3, name: 'Rent', kind: CategoryKind.expense, keywords: ['rent']),
    Category(id: 4, name: 'Akhira (charity)', kind: CategoryKind.expense, keywords: ['charity', 'sadaqah']),
    Category(id: 5, name: 'Other', kind: CategoryKind.expense),
    Category(id: 10, name: 'Salary', kind: CategoryKind.income, keywords: ['salary']),
    Category(id: 11, name: 'Other income', kind: CategoryKind.income),
  ];
  final parser = VoiceParser(categories);

  test('paid 90 for lunch', () {
    final d = parser.parse('Paid 90 for lunch');
    expect(d, hasLength(1));
    expect(d.single.type, TxnType.expense);
    expect(d.single.amountPaise, 9000);
    expect(d.single.categoryId, 1);
    expect(d.single.note, 'Lunch');
  });

  test('rent 2500 with rupee symbol and comma', () {
    final d = parser.parse('rent ₹2,500');
    expect(d.single.amountPaise, 250000);
    expect(d.single.categoryId, 3);
  });

  test('spoken numbers become digits', () {
    expect(VoiceParser.normalize('two hundred and fifty rupees for petrol'), '250 for petrol');
    expect(VoiceParser.normalize('one lakh twenty thousand'), '120000');
    expect(VoiceParser.normalize('2.5k'), '2500');
    final d = parser.parse('spent two hundred and fifty on petrol');
    expect(d.single.amountPaise, 25000);
    expect(d.single.categoryId, 2);
  });

  test('two entries in one sentence, shared account', () {
    final d = parser.parse('lunch 90 and tea 30 by cash');
    expect(d, hasLength(2));
    expect(d[0].amountPaise, 9000);
    expect(d[1].amountPaise, 3000);
    expect(d[1].note, 'Tea');
    expect(d.every((x) => x.accountHint == AccountKind.cash), isTrue);
  });

  test('words without an amount stay with their entry', () {
    final d = parser.parse('tea and snacks 50');
    expect(d, hasLength(1));
    expect(d.single.amountPaise, 5000);
    expect(d.single.categoryId, 1);
  });

  test('salary is income', () {
    final d = parser.parse('received 32185 salary');
    expect(d.single.type, TxnType.income);
    expect(d.single.categoryId, 10);
  });

  test('lending is a transfer, not an expense', () {
    final d = parser.parse('lent 500 to ameen');
    expect(d.single.type, TxnType.transfer);
    expect(d.single.toAccountHint, AccountKind.receivable);
    expect(d.single.payee, 'Ameen');
  });

  test('credit card bill is a transfer to the card', () {
    final d = parser.parse('paid credit card bill 16359');
    expect(d.single.type, TxnType.transfer);
    expect(d.single.accountHint, AccountKind.bank);
    expect(d.single.toAccountHint, AccountKind.creditCard);
  });

  test('unknown item falls back to Other', () {
    final d = parser.parse('paid 120 for haircut');
    expect(d.single.categoryId, 5);
    expect(d.single.note, 'Haircut');
  });

  test('category name with brackets still matches', () {
    expect(parser.parse('akhira 100').single.categoryId, 4);
  });

  test('nothing to record', () {
    expect(parser.parse('hello there'), isEmpty);
    expect(parser.parse(''), isEmpty);
  });
}
