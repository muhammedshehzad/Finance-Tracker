import 'package:finance_tracker/data/db/app_database.dart';
import 'package:finance_tracker/data/finance_repository.dart';
import 'package:finance_tracker/data/models/account.dart';
import 'package:finance_tracker/data/models/category.dart';
import 'package:finance_tracker/data/models/recurring_rule.dart';
import 'package:finance_tracker/data/models/txn.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late AppDatabase database;
  late FinanceRepository repo;
  late Map<AccountKind, int> acc;
  late int food;

  setUp(() async {
    database = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    repo = FinanceRepository(database);
    final accounts = await repo.accounts();
    acc = {for (final a in accounts) a.kind: a.id!};
    food = (await repo.categories(kind: CategoryKind.expense)).firstWhere((c) => c.name == 'Food').id!;
  });
  tearDown(() => database.close());

  Txn expense(int paise, {int? account, DateTime? date, String? upi}) => Txn(
    type: TxnType.expense,
    amount: paise,
    date: date ?? DateTime(2026, 11, 17, 13),
    accountId: account ?? acc[AccountKind.bank]!,
    categoryId: food,
    upiRef: upi,
  );

  test('seeds accounts and categories', () async {
    expect(acc.keys, containsAll([AccountKind.cash, AccountKind.bank, AccountKind.creditCard, AccountKind.receivable]));
    expect(await repo.categories(kind: CategoryKind.income), isNotEmpty);
  });

  test('opening balance plus activity gives the real balance', () async {
    final bank = (await repo.accounts()).firstWhere((a) => a.kind == AccountKind.bank);
    await repo.saveAccount(bank.copyWith(openingBalance: 4000000));
    await repo.saveTxn(expense(9000));
    expect((await repo.balances())[bank.id], 4000000 - 9000);
  });

  test('card spending plus bill payment is counted once as spending', () async {
    final card = acc[AccountKind.creditCard]!;
    final bank = acc[AccountKind.bank]!;
    await repo.saveTxn(expense(500000, account: card));
    await repo.saveTxn(
      Txn(type: TxnType.transfer, amount: 500000, date: DateTime(2026, 11, 20), accountId: bank, toAccountId: card),
    );
    final s = await repo.summary(DateTime(2026, 11), DateTime(2026, 12));
    expect(s.expense, 500000);
    final bal = await repo.balances();
    expect(bal[card], 0);
    expect(bal[bank], -500000);
  });

  test('lending moves money to a receivable, not to spending', () async {
    await repo.saveTxn(
      Txn(
        type: TxnType.transfer,
        amount: 50000,
        date: DateTime(2026, 11, 10),
        accountId: acc[AccountKind.bank]!,
        toAccountId: acc[AccountKind.receivable]!,
      ),
    );
    final s = await repo.summary(DateTime(2026, 11), DateTime(2026, 12));
    expect(s.expense, 0);
    final nw = await repo.netWorth();
    expect((await repo.balances())[acc[AccountKind.receivable]], 50000);
    expect(nw.assets, 50000);
    expect(nw.liabilities, 50000, reason: 'bank went below zero');
  });

  test('the same UPI reference cannot be saved twice', () async {
    await repo.saveTxn(expense(9000, upi: '534112345678'));
    expect(() => repo.saveTxn(expense(9000, upi: '534112345678')), throwsA(isA<DuplicatePaymentException>()));
  });

  test('summaries by day, month and category', () async {
    await repo.saveTxn(expense(9000, date: DateTime(2026, 11, 16, 13)));
    await repo.saveTxn(expense(800, date: DateTime(2026, 11, 16, 8)));
    await repo.saveTxn(expense(2600, date: DateTime(2026, 11, 17, 9)));
    final daily = await repo.dailySummaries(2026, 11);
    expect(daily[16]!.expense, 9800);
    final monthly = await repo.monthlySummaries(2026);
    expect(monthly[11]!.expense, 12400);
    final cats = await repo.categoryTotals(DateTime(2026, 11), DateTime(2026, 12), TxnType.expense);
    expect(cats.single.total, 12400);
  });

  test('budgets set and clear', () async {
    await repo.setBudget(food, 350000);
    await repo.setBudget(FinanceRepository.overallBudgetKey, 1150000);
    expect(await repo.budgets(), {food: 350000, 0: 1150000});
    await repo.setBudget(food, null);
    expect((await repo.budgets()).containsKey(food), isFalse);
  });

  test('posting a recurring rule records it and moves the due date', () async {
    final rent = (await repo.categories(kind: CategoryKind.expense)).firstWhere((c) => c.name == 'Rent');
    final id = await repo.saveRecurringRule(
      RecurringRule(
        type: TxnType.expense,
        amount: 250000,
        accountId: acc[AccountKind.bank]!,
        categoryId: rent.id,
        frequency: Frequency.monthly,
        startDate: DateTime(2026, 11, 5, 9),
        nextDue: DateTime(2026, 11, 5, 9),
      ),
    );
    final rule = (await repo.recurringRule(id))!;
    await repo.postRecurring(
      rule,
      Txn(type: TxnType.expense, amount: 250000, date: rule.nextDue, accountId: rule.accountId, categoryId: rent.id),
      DateTime(2026, 12, 5, 9),
    );
    expect((await repo.recurringRule(id))!.nextDue, DateTime(2026, 12, 5, 9));
    final txns = await repo.txnsBetween(DateTime(2026, 11), DateTime(2026, 12));
    expect(txns.single.recurringId, id);
  });
}
