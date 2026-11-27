import 'package:finance_tracker/data/models/txn.dart';
import 'package:finance_tracker/services/receipt_batch.dart';
import 'package:finance_tracker/services/receipt_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Txn saved(int paise, {TxnType type = TxnType.expense, String? payee, String note = ''}) =>
      Txn(type: type, amount: paise, date: DateTime(2026, 11, 25, 17), accountId: 1, payee: payee, note: note);

  ReceiptParseResult read(int paise, {String? payee}) =>
      ReceiptParseResult(amountPaise: paise, payee: payee, date: DateTime(2026, 11, 25), rawText: '');

  test('same amount and payee on the day is a duplicate', () {
    final match = saved(400000, payee: 'FATHIMATHUL MUSHIRIF');
    expect(likelyDuplicate(read(400000, payee: 'Fathimathul Mushirif'), TxnType.expense, [match]), match);
  });

  test('a payee only in the note still counts', () {
    final match = saved(9000, note: 'Swiggy');
    expect(likelyDuplicate(read(9000, payee: 'Swiggy Limited'), TxnType.expense, [match]), match);
  });

  test('a missing payee on either side matches on amount alone', () {
    final match = saved(2000);
    expect(likelyDuplicate(read(2000, payee: 'Tea stall'), TxnType.expense, [match]), match);
  });

  test('different payee, amount or direction is not a duplicate', () {
    expect(likelyDuplicate(read(2000, payee: 'Ameen K'), TxnType.expense, [saved(2000, payee: 'Rahul')]), isNull);
    expect(likelyDuplicate(read(2100), TxnType.expense, [saved(2000)]), isNull);
    expect(likelyDuplicate(read(2000), TxnType.income, [saved(2000)]), isNull);
  });
}
