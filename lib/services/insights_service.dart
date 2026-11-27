import 'package:intl/intl.dart';

import '../core/dates.dart';
import '../core/money.dart';
import '../data/models/txn.dart';

/// Whether an insight is good news, bad news or just a fact.
enum InsightTone { good, bad, neutral }

/// What an insight is about, which decides its icon.
enum InsightKind { pace, categoryUp, categoryDown, savings, daily, biggest, payee }

/// One short finding about a month, such as "Food is up ₹2,400".
class Insight {
  const Insight({required this.kind, required this.tone, required this.title, required this.detail, this.categoryId});

  final InsightKind kind;
  final InsightTone tone;
  final String title;
  final String detail;

  /// The category it is about, to open its entries.
  final int? categoryId;
}

/// What a month's entries show, compared with the month before.
class MonthInsights {
  const MonthInsights({required this.month, required this.items, this.comparedThroughDay});

  final DateTime month;
  final List<Insight> items;

  /// For the month in progress, the last day of both months that was
  /// compared, so a part month is weighed against the same days. Null for
  /// a finished month, which is compared whole.
  final int? comparedThroughDay;

  /// The one to show on the Stats screen.
  Insight? get headline => items.isEmpty ? null : items.first;
}

/// Works out a month's insights from its entries and the month before's.
/// Pure Dart, so every rule is unit tested. Transfers never count: they are
/// neither spending nor income.
abstract final class InsightsService {
  /// A category change smaller than this is noise, not news.
  static const minChange = 50000;

  /// Nor is one under a fifth of what it was.
  static const minShare = 0.2;

  static final _short = DateFormat('d MMM');
  static final _monthName = DateFormat('MMM');

  static MonthInsights build({
    required DateTime month,
    required DateTime now,
    required List<Txn> thisMonth,
    required List<Txn> lastMonth,
    required Map<int, String> categoryNames,
  }) {
    month = startOfMonth(month);
    final current = month.year == now.year && month.month == now.month;
    if (month.isAfter(now)) return MonthInsights(month: month, items: const []);

    final previous = DateTime(month.year, month.month - 1);
    final throughDay = current ? now.day : daysInMonth(month.year, month.month);
    final previousThrough = current ? throughDay.clamp(1, daysInMonth(previous.year, previous.month)) : 99;
    final endOfToday = startOfDay(now).add(const Duration(days: 1));

    bool inThis(Txn t) => t.date.isBefore(endOfToday) && t.date.day <= throughDay;
    bool inLast(Txn t) => t.date.day <= previousThrough;
    final spentNow = [
      for (final t in thisMonth)
        if (t.type == TxnType.expense && inThis(t)) t,
    ];
    final spentThen = [
      for (final t in lastMonth)
        if (t.type == TxnType.expense && inLast(t)) t,
    ];
    final cameIn = [
      for (final t in thisMonth)
        if (t.type == TxnType.income && inThis(t)) t,
    ];

    final spent = _sum(spentNow);
    final spentBefore = _sum(spentThen);
    final received = _sum(cameIn);
    final thisName = _monthName.format(month);
    final lastName = _monthName.format(previous);
    final items = <Insight>[];

    // Pace against last month.
    if (spentBefore > 0 && spent > 0) {
      final change = (spent - spentBefore) / spentBefore;
      final pct = (change.abs() * 100).round();
      final same = pct < 5;
      final word = change < 0 ? 'less' : 'more';
      items.add(
        Insight(
          kind: InsightKind.pace,
          tone: same ? InsightTone.neutral : (change < 0 ? InsightTone.good : InsightTone.bad),
          title: current
              ? (same
                    ? 'Spending is about the same as at this point in $lastName'
                    : 'You\'ve spent $pct% $word than at this point in $lastName')
              : (same ? 'You spent about the same as in $lastName' : 'You spent $pct% $word than in $lastName'),
          detail: current
              ? '${_money(spent)} so far, against ${_money(spentBefore)} by '
                    '${_short.format(DateTime(previous.year, previous.month, previousThrough))}.'
              : '${_money(spent)}, against ${_money(spentBefore)}.',
        ),
      );
    }

    // The category that rose most, and the one that fell most.
    final byNow = _byCategory(spentNow);
    final byThen = _byCategory(spentThen);
    final changes = <(int, int, int)>[
      for (final id in {...byNow.keys, ...byThen.keys}) (id, byNow[id] ?? 0, byThen[id] ?? 0),
    ];
    bool notable((int, int, int) c) {
      final (_, a, b) = c;
      return (a - b).abs() >= minChange && (b == 0 || (a - b).abs() / b >= minShare);
    }

    final rises = changes.where((c) => c.$2 > c.$3 && notable(c)).toList()
      ..sort((x, y) => (y.$2 - y.$3).compareTo(x.$2 - x.$3));
    final falls = changes.where((c) => c.$2 < c.$3 && notable(c)).toList()
      ..sort((x, y) => (x.$2 - x.$3).compareTo(y.$2 - y.$3));
    final when = current ? 'at this point in $lastName' : 'in $lastName';
    if (rises.isNotEmpty) {
      final (id, a, b) = rises.first;
      final name = categoryNames[id] ?? 'Other';
      items.add(
        Insight(
          kind: InsightKind.categoryUp,
          tone: InsightTone.bad,
          categoryId: id < 0 ? null : id,
          title: '$name is up ${_money(a - b)}',
          detail: b == 0
              ? '${_money(a)} on $name, with nothing there $when.'
              : '${_money(a)} against ${_money(b)} $when, ${((a - b) / b * 100).round()}% more.',
        ),
      );
    }
    if (falls.isNotEmpty) {
      final (id, a, b) = falls.first;
      final name = categoryNames[id] ?? 'Other';
      items.add(
        Insight(
          kind: InsightKind.categoryDown,
          tone: InsightTone.good,
          categoryId: id < 0 ? null : id,
          title: '$name is down ${_money(b - a)}',
          detail: a == 0
              ? 'Nothing on $name yet, against ${_money(b)} $when.'
              : '${_money(a)} against ${_money(b)} $when, ${((b - a) / b * 100).round()}% less.',
        ),
      );
    }

    // What was kept of what came in.
    if (received > 0) {
      final kept = received - spent;
      final rate = (kept / received * 100).round();
      items.add(
        Insight(
          kind: InsightKind.savings,
          tone: kept < 0 ? InsightTone.bad : (rate >= 10 ? InsightTone.good : InsightTone.neutral),
          title: kept < 0 ? 'You spent ${_money(-kept)} more than came in' : 'You kept $rate% of what came in',
          detail: '${_money(received)} in, ${_money(spent)} out${current ? ' so far' : ''}.',
        ),
      );
    }

    // The daily average, and where the month is heading.
    if (spent > 0) {
      final days = throughDay;
      final perDay = spent ~/ days;
      final monthDays = daysInMonth(month.year, month.month);
      final project = current && days >= 7 && days < monthDays;
      items.add(
        Insight(
          kind: InsightKind.daily,
          tone: InsightTone.neutral,
          title: '${_money(perDay)} a day on average',
          detail: project
              ? 'At this pace, about ${_money(perDay * monthDays)} by the end of $thisName.'
              : 'Over ${days == monthDays ? 'the $days days of $thisName' : 'the first $days days of $thisName'}.',
        ),
      );
    }

    // The single biggest expense.
    if (spentNow.isNotEmpty) {
      final top = spentNow.reduce((a, b) => b.amount > a.amount ? b : a);
      final what = _label(top) ?? categoryNames[top.categoryId] ?? 'An entry';
      items.add(
        Insight(
          kind: InsightKind.biggest,
          tone: InsightTone.neutral,
          categoryId: top.categoryId,
          title: 'Biggest spend: ${_money(top.amount)}',
          detail: '$what on ${_short.format(top.date)}.',
        ),
      );
    }

    // Where the money went most often.
    final byPayee = <String, List<Txn>>{};
    for (final t in spentNow) {
      final name = t.payee?.trim();
      if (name == null || name.isEmpty) continue;
      byPayee.putIfAbsent(name.toLowerCase(), () => []).add(t);
    }
    final frequent = byPayee.values.where((l) => l.length >= 3).toList()
      ..sort((a, b) => b.length != a.length ? b.length.compareTo(a.length) : _sum(b).compareTo(_sum(a)));
    if (frequent.isNotEmpty) {
      final l = frequent.first;
      items.add(
        Insight(
          kind: InsightKind.payee,
          tone: InsightTone.neutral,
          title: '${l.first.payee!.trim()}: ${l.length} payments',
          detail: '${_money(_sum(l))} in all${current ? ' so far' : ''} this month.',
        ),
      );
    }

    return MonthInsights(month: month, items: items, comparedThroughDay: current ? throughDay : null);
  }

  static int _sum(Iterable<Txn> txns) => txns.fold(0, (s, t) => s + t.amount);

  static Map<int, int> _byCategory(List<Txn> txns) {
    final out = <int, int>{};
    for (final t in txns) {
      out.update(t.categoryId ?? -1, (v) => v + t.amount, ifAbsent: () => t.amount);
    }
    return out;
  }

  static String? _label(Txn t) {
    for (final s in [t.payee, t.note]) {
      if (s != null && s.trim().isNotEmpty) return s.trim();
    }
    return null;
  }

  /// Rounded to whole rupees: insights are for reading, not reconciling.
  static String _money(Paise p) => formatMoney((p / 100).round() * 100);
}
