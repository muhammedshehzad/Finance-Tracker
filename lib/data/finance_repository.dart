import 'package:sqflite/sqflite.dart';

import '../core/dates.dart';
import 'db/app_database.dart';
import 'models/account.dart';
import 'models/captured_payment.dart';
import 'models/category.dart';
import 'models/recurring_rule.dart';
import 'models/txn.dart';

/// Thrown when a screenshot's UPI reference is already recorded.
class DuplicatePaymentException implements Exception {
  DuplicatePaymentException(this.existing);
  final Txn existing;

  @override
  String toString() => 'This payment (UPI ref ${existing.upiRef}) is already recorded.';
}

/// Income and expense over a period, in paise. Transfers are not counted.
class PeriodSummary {
  const PeriodSummary({required this.income, required this.expense});
  final int income;
  final int expense;
  int get net => income - expense;

  static const zero = PeriodSummary(income: 0, expense: 0);
}

/// The total for one category; a null id means uncategorised.
class CategoryTotal {
  const CategoryTotal(this.categoryId, this.total);
  final int? categoryId;
  final int total;
}

/// Net position across accounts, the way a balance sheet reads it.
class NetWorth {
  const NetWorth({required this.assets, required this.liabilities});

  /// Money you hold plus money others owe you.
  final int assets;

  /// Money you owe, e.g. credit card dues. Positive number.
  final int liabilities;
  int get net => assets - liabilities;
}

/// Single entry point for reading and writing finance data.
///
/// Income and expense totals never include transfers, so paying a credit
/// card bill or lending money moves balances without inflating spending.
class FinanceRepository {
  FinanceRepository(this._database);

  final AppDatabase _database;
  Database get _db => _database.db;

  Future<List<Account>> accounts({bool includeArchived = false}) async {
    final rows = await _db.query('accounts', where: includeArchived ? null : 'archived = 0', orderBy: 'sort_order, id');
    return rows.map(Account.fromMap).toList();
  }

  Future<int> saveAccount(Account a) async {
    if (a.id == null) return _db.insert('accounts', a.toMap());
    await _db.update('accounts', a.toMap(), where: 'id = ?', whereArgs: [a.id]);
    return a.id!;
  }

  /// Current balance of every account, in paise, keyed by account id.
  /// Positive means money you have (or are owed); negative on a credit card
  /// means money you owe.
  Future<Map<int, int>> balances({DateTime? asOf}) async {
    final dateFilter = asOf == null ? '' : 'AND t.date < ${asOf.millisecondsSinceEpoch}';
    final rows = await _db.rawQuery('''
      SELECT a.id AS id,
        a.opening_balance
        + COALESCE((SELECT SUM(t.amount) FROM transactions t
            WHERE t.account_id = a.id AND t.type = 'income' $dateFilter), 0)
        - COALESCE((SELECT SUM(t.amount) FROM transactions t
            WHERE t.account_id = a.id AND t.type IN ('expense', 'transfer') $dateFilter), 0)
        + COALESCE((SELECT SUM(t.amount) FROM transactions t
            WHERE t.to_account_id = a.id AND t.type = 'transfer' $dateFilter), 0)
        AS balance
      FROM accounts a''');
    return {for (final r in rows) r['id'] as int: (r['balance'] as int?) ?? 0};
  }

  Future<NetWorth> netWorth() async {
    final all = await accounts(includeArchived: true);
    final bal = await balances();
    var assets = 0;
    var liabilities = 0;
    for (final a in all) {
      final b = bal[a.id] ?? 0;
      if (b >= 0) {
        assets += b;
      } else {
        liabilities += -b;
      }
    }
    return NetWorth(assets: assets, liabilities: liabilities);
  }

  Future<List<Category>> categories({CategoryKind? kind, bool includeArchived = false}) async {
    final where = <String>[];
    final args = <Object>[];
    if (kind != null) {
      where.add('kind = ?');
      args.add(kind.name);
    }
    if (!includeArchived) where.add('archived = 0');
    final rows = await _db.query(
      'categories',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'sort_order, id',
    );
    return rows.map(Category.fromMap).toList();
  }

  Future<int> saveCategory(Category c) async {
    if (c.id == null) {
      final maxOrder = Sqflite.firstIntValue(await _db.rawQuery('SELECT MAX(sort_order) FROM categories')) ?? 0;
      return _db.insert('categories', c.copyWith(sortOrder: maxOrder + 1).toMap());
    }
    await _db.update('categories', c.toMap(), where: 'id = ?', whereArgs: [c.id]);
    return c.id!;
  }

  /// Saves a transaction. Throws [DuplicatePaymentException] when a new entry
  /// carries a UPI reference that is already recorded.
  Future<int> saveTxn(Txn t) async {
    _validate(t);
    if (t.upiRef != null && t.upiRef!.isNotEmpty) {
      final existing = await findByUpiRef(t.upiRef!);
      if (existing != null && existing.id != t.id) {
        throw DuplicatePaymentException(existing);
      }
    }
    if (t.id == null) return _db.insert('transactions', t.toMap());
    await _db.update('transactions', t.toMap(), where: 'id = ?', whereArgs: [t.id]);
    return t.id!;
  }

  void _validate(Txn t) {
    if (t.amount <= 0) throw ArgumentError('Amount must be more than zero');
    if (t.type == TxnType.transfer) {
      if (t.toAccountId == null) throw ArgumentError('A transfer needs a destination account');
      if (t.toAccountId == t.accountId) throw ArgumentError('Pick two different accounts');
    } else if (t.categoryId == null) {
      throw ArgumentError('Pick a category');
    }
  }

  /// Saves many entries in one database transaction, so an import either
  /// lands whole or not at all.
  Future<void> insertTxns(List<Txn> txns) async {
    for (final t in txns) {
      _validate(t);
    }
    await _db.transaction((tx) async {
      final batch = tx.batch();
      for (final t in txns) {
        batch.insert('transactions', t.toMap());
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> deleteTxn(int id) => _db.delete('transactions', where: 'id = ?', whereArgs: [id]);

  Future<Txn?> findByUpiRef(String upiRef) async {
    final rows = await _db.query('transactions', where: 'upi_ref = ?', whereArgs: [upiRef], limit: 1);
    return rows.isEmpty ? null : Txn.fromMap(rows.first);
  }

  /// Transactions with start <= date < end, newest first.
  Future<List<Txn>> txnsBetween(DateTime start, DateTime end, {int? categoryId, int? accountId, String? search}) async {
    final where = <String>['date >= ?', 'date < ?'];
    final args = <Object>[start.millisecondsSinceEpoch, end.millisecondsSinceEpoch];
    if (categoryId != null) {
      where.add('category_id = ?');
      args.add(categoryId);
    }
    if (accountId != null) {
      where.add('(account_id = ? OR to_account_id = ?)');
      args.addAll([accountId, accountId]);
    }
    if (search != null && search.trim().isNotEmpty) {
      where.add('(note LIKE ? OR description LIKE ? OR payee LIKE ?)');
      final q = '%${search.trim()}%';
      args.addAll([q, q, q]);
    }
    final rows = await _db.query(
      'transactions',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'date DESC, id DESC',
    );
    return rows.map(Txn.fromMap).toList();
  }

  Future<List<Txn>> allTxns() async {
    final rows = await _db.query('transactions', orderBy: 'date ASC, id ASC');
    return rows.map(Txn.fromMap).toList();
  }

  Future<PeriodSummary> summary(DateTime start, DateTime end) async {
    final rows = await _db.rawQuery(
      '''
      SELECT type, SUM(amount) AS total FROM transactions
      WHERE date >= ? AND date < ? AND type IN ('income', 'expense')
      GROUP BY type''',
      [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
    );
    var income = 0;
    var expense = 0;
    for (final r in rows) {
      if (r['type'] == 'income') income = r['total'] as int;
      if (r['type'] == 'expense') expense = r['total'] as int;
    }
    return PeriodSummary(income: income, expense: expense);
  }

  /// Totals per category for a period, largest first.
  Future<List<CategoryTotal>> categoryTotals(DateTime start, DateTime end, TxnType type) async {
    final rows = await _db.rawQuery(
      '''
      SELECT category_id, SUM(amount) AS total FROM transactions
      WHERE date >= ? AND date < ? AND type = ?
      GROUP BY category_id ORDER BY total DESC''',
      [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch, type.name],
    );
    return rows.map((r) => CategoryTotal(r['category_id'] as int?, r['total'] as int)).toList();
  }

  /// Income/expense per day of the month, keyed by day number (1-31).
  Future<Map<int, PeriodSummary>> dailySummaries(int year, int month) async {
    final txns = await txnsBetween(DateTime(year, month), DateTime(year, month + 1));
    final result = <int, PeriodSummary>{};
    for (final t in txns) {
      if (t.type == TxnType.transfer) continue;
      final cur = result[t.date.day] ?? PeriodSummary.zero;
      result[t.date.day] = t.type == TxnType.income
          ? PeriodSummary(income: cur.income + t.amount, expense: cur.expense)
          : PeriodSummary(income: cur.income, expense: cur.expense + t.amount);
    }
    return result;
  }

  /// Income/expense for each month of [year], keyed by month (1-12).
  Future<Map<int, PeriodSummary>> monthlySummaries(int year) async {
    final result = <int, PeriodSummary>{};
    for (var m = 1; m <= 12; m++) {
      result[m] = await summary(DateTime(year, m), DateTime(year, m + 1));
    }
    return result;
  }

  /// Category id 0 holds the overall monthly budget.
  static const overallBudgetKey = 0;

  Future<Map<int, int>> budgets() async {
    final rows = await _db.query('budgets');
    return {for (final r in rows) r['category_id'] as int: r['amount'] as int};
  }

  Future<void> setBudget(int categoryKey, int? amount) async {
    if (amount == null || amount <= 0) {
      await _db.delete('budgets', where: 'category_id = ?', whereArgs: [categoryKey]);
      return;
    }
    await _db.insert('budgets', {
      'category_id': categoryKey,
      'amount': amount,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<RecurringRule>> recurringRules({bool activeOnly = false}) async {
    final rows = await _db.query('recurring_rules', where: activeOnly ? 'active = 1' : null, orderBy: 'next_due ASC');
    return rows.map(RecurringRule.fromMap).toList();
  }

  Future<RecurringRule?> recurringRule(int id) async {
    final rows = await _db.query('recurring_rules', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : RecurringRule.fromMap(rows.first);
  }

  Future<int> saveRecurringRule(RecurringRule r) async {
    if (r.id == null) return _db.insert('recurring_rules', r.toMap());
    await _db.update('recurring_rules', r.toMap(), where: 'id = ?', whereArgs: [r.id]);
    return r.id!;
  }

  Future<void> deleteRecurringRule(int id) => _db.delete('recurring_rules', where: 'id = ?', whereArgs: [id]);

  /// Records [txn] and moves [rule] on to [nextDue] in one database transaction.
  Future<void> postRecurring(RecurringRule rule, Txn txn, DateTime nextDue, {bool deactivate = false}) async {
    _validate(txn);
    await _db.transaction((tx) async {
      await tx.insert('transactions', txn.copyWith(recurringId: rule.id).toMap());
      await tx.update(
        'recurring_rules',
        rule.copyWith(nextDue: nextDue, active: !deactivate).toMap(),
        where: 'id = ?',
        whereArgs: [rule.id],
      );
    });
  }

  /// Start of the earliest month that has data, for the monthly view.

  /// Stores a capture unless the same notification is already stored.
  /// Returns its id, or null when it was a repeat.
  Future<int?> insertCaptured(CapturedPayment c) async {
    final id = await _db.insert('captured_payments', c.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
    return id == 0 ? null : id;
  }

  Future<List<CapturedPayment>> capturedPayments({CaptureStatus? status, DateTime? since}) async {
    final where = <String>[];
    final args = <Object>[];
    if (status != null) {
      where.add('status = ?');
      args.add(status.name);
    }
    if (since != null) {
      where.add('posted_at >= ?');
      args.add(since.millisecondsSinceEpoch);
    }
    final rows = await _db.query(
      'captured_payments',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'posted_at DESC, id DESC',
    );
    return rows.map(CapturedPayment.fromMap).toList();
  }

  Future<void> setCaptureStatus(int id, CaptureStatus status, {int? txnId}) =>
      _db.update('captured_payments', {'status': status.name, 'txn_id': ?txnId}, where: 'id = ?', whereArgs: [id]);

  /// Drops handled captures older than [age]; pending ones are kept.
  Future<void> pruneCaptured({Duration age = const Duration(days: 90)}) => _db.delete(
    'captured_payments',
    where: "status != 'pending' AND posted_at < ?",
    whereArgs: [DateTime.now().subtract(age).millisecondsSinceEpoch],
  );

  Future<DateTime?> firstTxnDate() async {
    final v = Sqflite.firstIntValue(await _db.rawQuery('SELECT MIN(date) FROM transactions'));
    return v == null ? null : startOfDay(DateTime.fromMillisecondsSinceEpoch(v));
  }
}
