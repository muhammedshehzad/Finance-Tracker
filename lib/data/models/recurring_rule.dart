import 'txn.dart';

/// How often a recurring payment repeats.
enum Frequency {
  daily('Daily', 'day'),
  weekly('Weekly', 'week'),
  monthly('Monthly', 'month'),
  yearly('Yearly', 'year');

  const Frequency(this.label, this.unit);
  final String label;
  final String unit;
}

/// A payment or income that repeats: rent, EMI, subscriptions, salary.
class RecurringRule {
  factory RecurringRule.fromMap(Map<String, Object?> m) => RecurringRule(
    id: m['id'] as int,
    type: TxnType.values.byName(m['type'] as String),
    amount: m['amount'] as int,
    accountId: m['account_id'] as int,
    categoryId: m['category_id'] as int?,
    toAccountId: m['to_account_id'] as int?,
    note: (m['note'] as String?) ?? '',
    frequency: Frequency.values.byName(m['frequency'] as String),
    interval: m['interval'] as int,
    startDate: DateTime.fromMillisecondsSinceEpoch(m['start_date'] as int),
    endDate: m['end_date'] == null ? null : DateTime.fromMillisecondsSinceEpoch(m['end_date'] as int),
    nextDue: DateTime.fromMillisecondsSinceEpoch(m['next_due'] as int),
    autoPost: (m['auto_post'] as int) == 1,
    remindDaysBefore: m['remind_days_before'] as int,
    active: (m['active'] as int) == 1,
  );

  const RecurringRule({
    this.id,
    required this.type,
    required this.amount,
    required this.accountId,
    this.categoryId,
    this.toAccountId,
    this.note = '',
    required this.frequency,
    this.interval = 1,
    required this.startDate,
    this.endDate,
    required this.nextDue,
    this.autoPost = false,
    this.remindDaysBefore = 1,
    this.active = true,
  });

  final int? id;
  final TxnType type;
  final int amount;
  final int accountId;
  final int? categoryId;
  final int? toAccountId;
  final String note;
  final Frequency frequency;

  /// Every [interval] units, e.g. 3 + monthly = quarterly.
  final int interval;
  final DateTime startDate;
  final DateTime? endDate;

  /// The next date this rule is due and not yet recorded or skipped.
  final DateTime nextDue;

  /// When true, due occurrences are recorded automatically on app start.
  /// When false (the default) they wait in "Due now" for you to confirm.
  final bool autoPost;

  /// Days before [nextDue] to send a reminder. Negative disables reminders.
  final int remindDaysBefore;
  final bool active;

  /// Day of month the rule is pinned to, so 31st stays 31st after February.
  int get anchorDay => startDate.day;

  String get scheduleLabel {
    if (interval == 1) return frequency.label;
    return 'Every $interval ${frequency.unit}s';
  }

  RecurringRule copyWith({
    int? id,
    TxnType? type,
    int? amount,
    int? accountId,
    int? categoryId,
    int? toAccountId,
    String? note,
    Frequency? frequency,
    int? interval,
    DateTime? startDate,
    DateTime? endDate,
    bool clearEndDate = false,
    DateTime? nextDue,
    bool? autoPost,
    int? remindDaysBefore,
    bool? active,
  }) => RecurringRule(
    id: id ?? this.id,
    type: type ?? this.type,
    amount: amount ?? this.amount,
    accountId: accountId ?? this.accountId,
    categoryId: categoryId ?? this.categoryId,
    toAccountId: toAccountId ?? this.toAccountId,
    note: note ?? this.note,
    frequency: frequency ?? this.frequency,
    interval: interval ?? this.interval,
    startDate: startDate ?? this.startDate,
    endDate: clearEndDate ? null : (endDate ?? this.endDate),
    nextDue: nextDue ?? this.nextDue,
    autoPost: autoPost ?? this.autoPost,
    remindDaysBefore: remindDaysBefore ?? this.remindDaysBefore,
    active: active ?? this.active,
  );

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'type': type.name,
    'amount': amount,
    'account_id': accountId,
    'category_id': categoryId,
    'to_account_id': toAccountId,
    'note': note,
    'frequency': frequency.name,
    'interval': interval,
    'start_date': startDate.millisecondsSinceEpoch,
    'end_date': endDate?.millisecondsSinceEpoch,
    'next_due': nextDue.millisecondsSinceEpoch,
    'auto_post': autoPost ? 1 : 0,
    'remind_days_before': remindDaysBefore,
    'active': active ? 1 : 0,
  };
}
