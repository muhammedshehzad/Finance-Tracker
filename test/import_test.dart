import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:finance_tracker/data/models/account.dart';
import 'package:finance_tracker/data/models/category.dart';
import 'package:finance_tracker/data/models/txn.dart';
import 'package:finance_tracker/services/import/import_planner.dart';
import 'package:finance_tracker/services/import/sheet_reader.dart';
import 'package:finance_tracker/services/import/table_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// Shaped like a Money Manager "Export to Excel" file, saved as CSV.
const moneyManagerCsv = '''
Period,Accounts,Category,Subcategory,Note,INR,Income/Expense,Description,Amount,Currency,Accounts
26/11/2026 09:12:00,Accounts,Food,Breakfast,Breakfast,8,Exp.,,8,INR,8
26/11/2026 13:40:00,Accounts,Food,,Lunch,90,Exp.,with team,90,INR,90
25/11/2026 18:05:00,Accounts,Credit Card Bill,,HDFC bill,"16,359.00",Exp.,,16359,INR,16359
24/11/2026 10:00:00,Accounts,Salary,,November,"32,185",Income,,32185,INR,32185
23/11/2026 20:00:00,Accounts,Cash,,ATM,500,Transfer-Out,,500,INR,500
23/11/2026 20:00:00,Cash,Accounts,,ATM,500,Transfer-In,,500,INR,500
22/11/2026 08:30:00,Cash,Transport,,Bus,26,Exp.,,26,INR,26
31/12/2025 21:00:00,Accounts,Food,,Dinner,300,Exp.,,300,INR,300
not a date,Accounts,Food,,Broken,40,Exp.,,40,INR,40
''';

List<List<Object?>> _csv(String s) => const SheetReader().readCsv(Uint8List.fromList(utf8.encode(s)));

void main() {
  const parser = TableParser();
  const planner = ImportPlanner();

  group('values', () {
    test('amounts', () {
      expect(TableParser.parseAmount('₹1,234.50'), 123450);
      expect(TableParser.parseAmount('Rs. 90'), 9000);
      expect(TableParser.parseAmount('(250)'), -25000);
      expect(TableParser.parseAmount('-36'), -3600);
      expect(TableParser.parseAmount('1,250 Dr'), -125000);
      expect(TableParser.parseAmount('INR 1,00,000'), 10000000);
      expect(TableParser.parseAmount(16359), 1635900);
      expect(TableParser.parseAmount(12.345), 1235);
      expect(TableParser.parseAmount('abc'), isNull);
    });

    test('dates', () {
      expect(TableParser.parseDate('26/11/2026 13:40:00'), DateTime(2026, 11, 26, 13, 40));
      expect(TableParser.parseDate('03/04/2026'), DateTime(2026, 4, 3));
      expect(TableParser.parseDate('03/04/2026', dayFirst: false), DateTime(2026, 3, 4));
      expect(TableParser.parseDate('11/26/2026'), DateTime(2026, 11, 26), reason: '26 cannot be a month');
      expect(TableParser.parseDate('2026-11-26 7:05 pm'), DateTime(2026, 11, 26, 19, 5));
      expect(TableParser.parseDate('26 Nov 2026'), DateTime(2026, 11, 26));
      expect(TableParser.parseDate('Nov 26, 2026'), DateTime(2026, 11, 26));
      expect(TableParser.parseDate(46352), DateTime(2026, 11, 26), reason: 'Excel serial');
      expect(TableParser.parseDate(46352.5), DateTime(2026, 11, 26, 12));
      expect(TableParser.parseDate('31/02/2026'), isNull);
      expect(TableParser.parseDate('hello'), isNull);
    });

    test('types', () {
      expect(TableParser.parseKind('Exp.'), RowKind.expense);
      expect(TableParser.parseKind('Expense'), RowKind.expense);
      expect(TableParser.parseKind('Income'), RowKind.income);
      expect(TableParser.parseKind('Transfer-Out'), RowKind.transferOut);
      expect(TableParser.parseKind('Transfer-In'), RowKind.transferIn);
      expect(TableParser.parseKind('Dr'), RowKind.expense);
      expect(TableParser.parseKind('refund?'), isNull);
    });
  });

  group('Money Manager export', () {
    late List<List<Object?>> rows;
    late Map<int, ImportField> columns;
    late List<ParsedRow> parsed;

    setUp(() {
      rows = _csv(moneyManagerCsv);
      final header = parser.findHeaderRow(rows);
      columns = parser.guessColumns(rows[header]);
      parsed = parser.parse(rows, header, columns, const ParseOptions());
    });

    test('guesses the columns, preferring INR and the first Accounts', () {
      expect(columns[0], ImportField.date);
      expect(columns[1], ImportField.account);
      expect(columns[2], ImportField.category);
      expect(columns[3], ImportField.subcategory);
      expect(columns[4], ImportField.note);
      expect(columns[5], ImportField.amount);
      expect(columns[6], ImportField.type);
      expect(columns[7], ImportField.description);
      expect(columns[8], ImportField.ignore, reason: 'INR already holds the amount');
      expect(columns[10], ImportField.ignore, reason: 'second Accounts column');
    });

    test('parses rows and flags the broken one', () {
      expect(parsed, hasLength(9));
      expect(parsed.where((r) => !r.ok).single.rowNumber, 10);
      final bill = parsed.firstWhere((r) => r.category == 'Credit Card Bill');
      expect(bill.amount, 1635900);
      expect(bill.kind, RowKind.expense);
    });

    test('plans the current year, merging the transfer pair', () {
      final plan = planner.plan(parsed, year: 2026);
      expect(plan.errors, hasLength(1));
      expect(plan.mergedTransferIns, 1);
      expect(plan.entries, hasLength(6));
      final transfer = plan.entries.singleWhere((e) => e.type == TxnType.transfer);
      expect(transfer.fromAccount, 'Accounts');
      expect(transfer.toAccount, 'Cash');
      expect(plan.total(TxnType.expense), 800 + 9000 + 1635900 + 2600);
      expect(plan.total(TxnType.income), 3218500);
      expect(plan.firstDate, DateTime(2026, 11, 22, 8, 30));
      expect(planner.plan(parsed).entries, hasLength(7), reason: 'all years keeps Dec 2025');
    });

    test('suggests same-named targets and resolves with dedupe', () {
      final plan = planner.plan(parsed, year: 2026);
      final accounts = [
        const Account(id: 1, name: 'Cash', kind: AccountKind.cash),
        const Account(id: 2, name: 'Bank', kind: AccountKind.bank),
        const Account(id: 3, name: 'Credit card', kind: AccountKind.creditCard),
      ];
      final categories = [
        const Category(id: 10, name: 'Food', kind: CategoryKind.expense),
        const Category(id: 11, name: 'Salary', kind: CategoryKind.income),
      ];
      final mapping = planner.suggest(plan, accounts, categories);
      expect(mapping.accounts['Cash']!.accountId, 1);
      expect(mapping.accounts['Accounts']!.isNew, isTrue);
      expect(mapping.accounts['Accounts']!.newKind, AccountKind.bank);
      expect(mapping.categories[const SourceCategory('Food', CategoryKind.expense)]!.categoryId, 10);
      const bill = SourceCategory('Credit Card Bill', CategoryKind.expense);
      expect(mapping.categories[bill]!.action, CategoryAction.create, reason: 'never turned into a transfer unasked');
      expect(bill.looksLikeTransfer, isTrue);

      mapping.accounts['Accounts'] = const AccountChoice.existing(2);
      mapping.categories[bill] = const CategoryChoice.transfer(3);
      final ids = {'Accounts': 2, 'Cash': 1};
      final catIds = {
        const SourceCategory('Food', CategoryKind.expense): 10,
        const SourceCategory('Salary', CategoryKind.income): 11,
        const SourceCategory('Transport', CategoryKind.expense): 12,
      };

      final first = planner.resolve(plan, mapping, accountIds: ids, categoryIds: catIds, existing: const []);
      expect(first.txns, hasLength(6));
      final billTxn = first.txns.singleWhere((t) => t.amount == 1635900);
      expect(billTxn.type, TxnType.transfer);
      expect(billTxn.accountId, 2);
      expect(billTxn.toAccountId, 3);
      expect(billTxn.categoryId, isNull);
      final breakfast = first.txns.singleWhere((t) => t.amount == 800);
      expect(breakfast.description, 'Breakfast');
      expect(breakfast.source, TxnSource.imported);

      final again = planner.resolve(plan, mapping, accountIds: ids, categoryIds: catIds, existing: first.txns);
      expect(again.txns, isEmpty);
      expect(again.duplicates, 6);
    });

    test('a lent-money income row becomes a transfer back from the receivable', () {
      final rows = parser.parse(
        _csv('Date,Type,Amount,Category,Account\n01/11/2026,Income,500,Lended money,Bank\n'),
        0,
        {
          0: ImportField.date,
          1: ImportField.type,
          2: ImportField.amount,
          3: ImportField.category,
          4: ImportField.account,
        },
        const ParseOptions(),
      );
      final plan = planner.plan(rows);
      final mapping = ImportMapping(
        accounts: {'Bank': const AccountChoice.existing(2)},
        categories: {const SourceCategory('Lended money', CategoryKind.income): const CategoryChoice.transfer(4)},
      );
      final t = planner.resolve(plan, mapping, accountIds: {'Bank': 2}, categoryIds: {}, existing: []).txns.single;
      expect(t.type, TxnType.transfer);
      expect(t.accountId, 4);
      expect(t.toAccountId, 2);
    });
  });

  test('bank statement with debit and credit columns and no type', () {
    const csv = '''
Statement of account
Txn Date,Narration,Withdrawal Amt.,Deposit Amt.,Closing Balance
02-11-2026,UPI-ZOMATO,450.00,,10000
03-11-2026,SALARY NOV,,"50,000.00",60000
''';
    final rows = _csv(csv);
    final header = parser.findHeaderRow(rows);
    expect(header, 1);
    final columns = parser.guessColumns(rows[header]);
    expect(columns[0], ImportField.date);
    expect(columns[1], ImportField.note);
    expect(columns[2], ImportField.expense);
    expect(columns[3], ImportField.income);
    final parsed = parser.parse(rows, header, columns, const ParseOptions());
    expect(parsed[0].kind, RowKind.expense);
    expect(parsed[0].amount, 45000);
    expect(parsed[1].kind, RowKind.income);
    expect(parsed[1].amount, 5000000);
  });

  test('reads an xlsx with date cells and the busiest sheet', () {
    final book = Excel.createExcel();
    final notes = book['Notes'];
    notes.appendRow([TextCellValue('just a note')]);
    final data = book['Data'];
    data.appendRow([TextCellValue('Date'), TextCellValue('Amount'), TextCellValue('Category'), TextCellValue('Type')]);
    data.appendRow([
      DateCellValue(year: 2026, month: 11, day: 3),
      DoubleCellValue(120.5),
      TextCellValue('Food'),
      TextCellValue('Expense'),
    ]);
    data.appendRow([
      DateCellValue(year: 2026, month: 11, day: 4),
      IntCellValue(900),
      TextCellValue('Rent'),
      TextCellValue('Expense'),
    ]);
    final bytes = Uint8List.fromList(book.encode()!);

    final sheet = const SheetReader().read('money.xlsx', bytes);
    expect(sheet.name, 'Data');
    final header = parser.findHeaderRow(sheet.rows);
    final parsed = parser.parse(sheet.rows, header, parser.guessColumns(sheet.rows[header]), const ParseOptions());
    expect(parsed, hasLength(2));
    expect(parsed[0].date, DateTime(2026, 11, 3));
    expect(parsed[0].amount, 12050);
    expect(parsed[1].amount, 90000);
  });

  test('header words that only look like money stay text', () {
    final c = parser.guessColumns(['Date', 'Particulars', 'Paid to', 'Amount paid', 'Rs']);
    expect(c[1], ImportField.note);
    expect(c[2], isNot(ImportField.expense));
    expect(c[3], ImportField.expense);
    expect(c[4], ImportField.amount);
  });

  test('old .xls is refused with a clear message', () {
    expect(() => const SheetReader().read('old.xls', Uint8List(4)), throwsA(isA<UnsupportedFileException>()));
  });
}
