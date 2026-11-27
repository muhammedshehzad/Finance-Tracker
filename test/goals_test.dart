import 'package:finance_tracker/data/db/app_database.dart';
import 'package:finance_tracker/data/finance_repository.dart';
import 'package:finance_tracker/data/models/goal.dart';
import 'package:finance_tracker/services/backup_service.dart';
import 'package:finance_tracker/ui/goals/goal_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late AppDatabase database;
  late FinanceRepository repo;
  final start = DateTime(2026, 11, 27);

  setUpAll(() async {
    Intl.defaultLocale = 'en_IN';
    await initializeDateFormatting('en_IN');
  });

  setUp(() async {
    database = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    repo = FinanceRepository(database);
  });
  tearDown(() => database.close());

  Future<int> goa({DateTime? by}) =>
      repo.saveGoal(Goal(name: 'Goa trip', emoji: '✈️', target: 3000000, targetDate: by, createdAt: start));

  test('saved is what went in minus what came out, and accounts are untouched', () async {
    final balancesBefore = await repo.balances();
    final id = await goa();
    await repo.addGoalEntry(GoalEntry(goalId: id, amount: 1000000, date: start));
    await repo.addGoalEntry(GoalEntry(goalId: id, amount: 500000, date: start));
    await repo.addGoalEntry(GoalEntry(goalId: id, amount: -200000, date: start, note: 'Deposit'));

    final p = (await repo.goal(id))!;
    expect(p.saved, 1300000);
    expect(p.left, 1700000);
    expect(p.reached, isFalse);
    expect((await repo.goalEntries(id)).map((e) => e.amount), [-200000, 500000, 1000000]);
    expect(await repo.balances(), balancesBefore);
  });

  test('archived goals leave the main list, and deleting one takes its history', () async {
    final id = await goa();
    await repo.addGoalEntry(GoalEntry(goalId: id, amount: 1000, date: start));
    await repo.saveGoal((await repo.goal(id))!.goal.copyWith(archived: true));
    expect(await repo.goals(), isEmpty);
    expect((await repo.goals(archived: true)).single.saved, 1000);

    await repo.deleteGoal(id);
    expect(await repo.goal(id), isNull);
    expect(await database.db.query('goal_entries'), isEmpty);
  });

  test('a goal without an amount, or an empty entry, is refused', () async {
    expect(() => repo.saveGoal(Goal(name: 'x', target: 0, createdAt: start)), throwsA(isA<DatabaseException>()));
    final id = await goa();
    expect(() => repo.addGoalEntry(GoalEntry(goalId: id, amount: 0, date: start)), throwsA(isA<DatabaseException>()));
  });

  test('monthly amount counts the month of the date too', () {
    final g = Goal(name: 'Phone', target: 6000000, targetDate: DateTime(2027, 4, 30), createdAt: start);
    // Nov, Dec, Jan, Feb, Mar, Apr: six months for ₹60,000, with ₹12,000 in.
    final p = GoalProgress(g, 1200000);
    expect(p.monthlyNeeded(start), 800000);
    expect(goalLine(p, start), '₹8,000 a month to reach it by Apr 2027');
    expect(GoalProgress(g, 6000000).monthlyNeeded(start), isNull);
    expect(goalLine(GoalProgress(g, 6000000), start), 'Reached');
    expect(p.monthlyNeeded(DateTime(2027, 5, 1)), isNull, reason: 'the date has passed');
    expect(goalLine(p, DateTime(2027, 5, 1)), contains('has passed'));
    expect(goalLine(GoalProgress(g.copyWith(clearDate: true), 1200000), start), '₹48,000 to go');
  });

  test('goals go into backups and come back', () async {
    final id = await goa(by: DateTime(2027, 3, 1));
    await repo.addGoalEntry(GoalEntry(goalId: id, amount: 250000, date: start, note: 'Bonus'));
    final backup = BackupService(repo.database);
    final saved = await backup.export(now: start);
    await repo.deleteGoal(id);
    await backup.restore(saved);
    final p = (await repo.goals()).single;
    expect(p.goal.name, 'Goa trip');
    expect(p.goal.targetDate, DateTime(2027, 3, 1));
    expect(p.saved, 250000);
  });
}
