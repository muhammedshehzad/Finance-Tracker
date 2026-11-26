import 'package:finance_tracker/data/models/recurring_rule.dart';
import 'package:finance_tracker/data/models/txn.dart';
import 'package:finance_tracker/services/recurring_engine.dart';
import 'package:flutter_test/flutter_test.dart';

RecurringRule rule({
  Frequency f = Frequency.monthly,
  int interval = 1,
  required DateTime start,
  DateTime? next,
  DateTime? end,
  int remind = 1,
}) => RecurringRule(
  id: 1,
  type: TxnType.expense,
  amount: 250000,
  accountId: 1,
  categoryId: 3,
  frequency: f,
  interval: interval,
  startDate: start,
  nextDue: next ?? start,
  endDate: end,
  remindDaysBefore: remind,
);

void main() {
  const engine = RecurringEngine();

  test('monthly on the 31st clamps to month end and comes back', () {
    final r = rule(start: DateTime(2026, 1, 31, 9));
    final feb = engine.advance(r, r.startDate);
    expect(feb, DateTime(2026, 2, 28, 9));
    final mar = engine.advance(r, feb);
    expect(mar, DateTime(2026, 3, 31, 9));
  });

  test('weekly and every 3 months', () {
    expect(
      engine.advance(rule(f: Frequency.weekly, start: DateTime(2026, 11, 26)), DateTime(2026, 11, 26)),
      DateTime(2026, 12, 3),
    );
    final q = rule(interval: 3, start: DateTime(2026, 11, 5));
    expect(engine.advance(q, q.startDate), DateTime(2027, 2, 5));
  });

  test('due occurrences catch up missed months', () {
    final r = rule(start: DateTime(2026, 9, 5, 9));
    final due = engine.dueOccurrences(r, DateTime(2026, 11, 26));
    expect(due, [DateTime(2026, 9, 5, 9), DateTime(2026, 10, 5, 9), DateTime(2026, 11, 5, 9)]);
  });

  test('nothing due before the date, and nothing after the end date', () {
    final r = rule(start: DateTime(2026, 12, 1));
    expect(engine.dueOccurrences(r, DateTime(2026, 11, 26)), isEmpty);
    final ended = rule(start: DateTime(2026, 9, 5), end: DateTime(2026, 10, 10));
    expect(engine.dueOccurrences(ended, DateTime(2026, 11, 26)), hasLength(2));
  });

  test('due today counts', () {
    final r = rule(start: DateTime(2026, 11, 26, 9));
    expect(engine.isDue(r, DateTime(2026, 11, 26, 8)), isTrue);
  });

  test('reminder time and opting out', () {
    expect(engine.reminderTime(rule(start: DateTime(2026, 12, 5, 9), remind: 2)), DateTime(2026, 12, 3, 9));
    expect(engine.reminderTime(rule(start: DateTime(2026, 12, 5), remind: -1)), isNull);
  });

  test('generated transaction is marked recurring', () {
    final r = rule(start: DateTime(2026, 11, 5));
    final t = engine.txnFor(r, DateTime(2026, 11, 5));
    expect(t.source, TxnSource.recurring);
    expect(t.recurringId, 1);
    expect(t.amount, 250000);
  });
}
