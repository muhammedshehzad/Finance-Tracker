import '../../core/money.dart';

/// Something you are saving toward, such as a trip or an emergency fund.
///
/// A goal doesn't move money between accounts: putting money in records
/// that you set it aside, so it never changes a balance or your spending.
class Goal {
  factory Goal.fromMap(Map<String, Object?> m) => Goal(
    id: m['id'] as int,
    name: m['name'] as String,
    emoji: m['emoji'] as String,
    target: m['target'] as int,
    targetDate: m['target_date'] == null ? null : DateTime.fromMillisecondsSinceEpoch(m['target_date'] as int),
    archived: (m['archived'] as int) == 1,
    createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
  );

  const Goal({
    this.id,
    required this.name,
    this.emoji = '🎯',
    required this.target,
    this.targetDate,
    this.archived = false,
    required this.createdAt,
  });

  final int? id;
  final String name;
  final String emoji;

  /// The amount to reach, in paise. Always more than zero.
  final Paise target;

  /// The day to reach it by, if there is one.
  final DateTime? targetDate;

  /// Finished or given up: kept for the record, out of the main list.
  final bool archived;
  final DateTime createdAt;

  Goal copyWith({
    String? name,
    String? emoji,
    Paise? target,
    DateTime? targetDate,
    bool clearDate = false,
    bool? archived,
  }) => Goal(
    id: id,
    name: name ?? this.name,
    emoji: emoji ?? this.emoji,
    target: target ?? this.target,
    targetDate: clearDate ? null : (targetDate ?? this.targetDate),
    archived: archived ?? this.archived,
    createdAt: createdAt,
  );

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'name': name,
    'emoji': emoji,
    'target': target,
    'target_date': targetDate?.millisecondsSinceEpoch,
    'archived': archived ? 1 : 0,
    'created_at': createdAt.millisecondsSinceEpoch,
  };
}

/// Money put into a goal (a positive amount) or taken out (negative).
class GoalEntry {
  factory GoalEntry.fromMap(Map<String, Object?> m) => GoalEntry(
    id: m['id'] as int,
    goalId: m['goal_id'] as int,
    amount: m['amount'] as int,
    date: DateTime.fromMillisecondsSinceEpoch(m['date'] as int),
    note: m['note'] as String,
  );

  const GoalEntry({this.id, required this.goalId, required this.amount, required this.date, this.note = ''});

  final int? id;
  final int goalId;
  final Paise amount;
  final DateTime date;
  final String note;

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'goal_id': goalId,
    'amount': amount,
    'date': date.millisecondsSinceEpoch,
    'note': note,
  };
}

/// A goal with what has been saved toward it so far.
class GoalProgress {
  const GoalProgress(this.goal, this.saved);

  final Goal goal;

  /// Everything put in minus everything taken out, in paise.
  final Paise saved;

  Paise get left => (goal.target - saved).clamp(0, goal.target);
  bool get reached => saved >= goal.target;
  double get fraction => (saved / goal.target).clamp(0, 1).toDouble();

  /// What to put in each month from [now] to reach the goal by its date,
  /// counting the month of the date itself. Null without a date, when it is
  /// reached, or when the date has passed.
  Paise? monthlyNeeded(DateTime now) {
    final by = goal.targetDate;
    if (by == null || reached) return null;
    final today = DateTime(now.year, now.month, now.day);
    if (by.isBefore(today)) return null;
    final months = (by.year - now.year) * 12 + by.month - now.month + 1;
    return (left / months).ceil();
  }
}
