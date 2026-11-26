import '../core/dates.dart';
import '../data/models/recurring_rule.dart';
import '../data/models/txn.dart';

/// Pure date maths for recurring rules. No I/O, so it is unit tested directly.
class RecurringEngine {
  const RecurringEngine();

  /// The occurrence after [from] for [rule].
  DateTime advance(RecurringRule rule, DateTime from) {
    final n = rule.interval < 1 ? 1 : rule.interval;
    switch (rule.frequency) {
      case Frequency.daily:
        return DateTime(from.year, from.month, from.day + n, from.hour, from.minute);
      case Frequency.weekly:
        return DateTime(from.year, from.month, from.day + 7 * n, from.hour, from.minute);
      case Frequency.monthly:
        return addMonthsClamped(from, n, rule.anchorDay);
      case Frequency.yearly:
        return addMonthsClamped(from, 12 * n, rule.anchorDay);
    }
  }

  /// True when [date] falls after the rule's end date.
  bool isPastEnd(RecurringRule rule, DateTime date) {
    final end = rule.endDate;
    if (end == null) return false;
    return date.isAfter(DateTime(end.year, end.month, end.day, 23, 59, 59));
  }

  /// Every occurrence from the rule's next due date up to and including
  /// today, oldest first. Capped at [max] so a rule left alone for years
  /// can't flood the database.
  List<DateTime> dueOccurrences(RecurringRule rule, DateTime now, {int max = 60}) {
    if (!rule.active) return const [];
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final result = <DateTime>[];
    var d = rule.nextDue;
    while (!d.isAfter(endOfToday) && !isPastEnd(rule, d) && result.length < max) {
      result.add(d);
      d = advance(rule, d);
    }
    return result;
  }

  bool isDue(RecurringRule rule, DateTime now) => dueOccurrences(rule, now, max: 1).isNotEmpty;

  /// The transaction a rule produces for one occurrence.
  Txn txnFor(RecurringRule rule, DateTime date) => Txn(
    type: rule.type,
    amount: rule.amount,
    date: date,
    accountId: rule.accountId,
    categoryId: rule.type == TxnType.transfer ? null : rule.categoryId,
    toAccountId: rule.type == TxnType.transfer ? rule.toAccountId : null,
    note: rule.note,
    source: TxnSource.recurring,
    recurringId: rule.id,
  );

  /// When to remind about the rule's next occurrence: [remindDaysBefore]
  /// days ahead at [hour]:00. Null when reminders are off for this rule.
  DateTime? reminderTime(RecurringRule rule, {int hour = 9}) {
    if (!rule.active || rule.remindDaysBefore < 0) return null;
    final d = rule.nextDue;
    return DateTime(d.year, d.month, d.day - rule.remindDaysBefore, hour);
  }

  /// First due date for a new rule starting on [start].
  DateTime firstDue(DateTime start) => startOfDay(start).add(const Duration(hours: 9));
}
