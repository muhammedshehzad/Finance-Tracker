/// Date helpers. All dates in the app are local device time.
library;

import 'package:intl/intl.dart';

/// Midnight at the start of [d].
DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

/// Midnight on the first day of [d]'s month.
DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month);

/// First instant of the next month. Use as an exclusive upper bound.
DateTime startOfNextMonth(DateTime d) => DateTime(d.year, d.month + 1);

int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

bool isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Adds [months] to [from] keeping the day of month at [anchorDay], clamped to
/// the length of the target month (31 Jan + 1 month -> 28/29 Feb, then back
/// to 31 Mar). Time of day is preserved.
DateTime addMonthsClamped(DateTime from, int months, int anchorDay) {
  final totalMonths = from.year * 12 + (from.month - 1) + months;
  final year = totalMonths ~/ 12;
  final month = totalMonths % 12 + 1;
  final day = anchorDay.clamp(1, daysInMonth(year, month));
  return DateTime(year, month, day, from.hour, from.minute);
}

final DateFormat monthYearFormat = DateFormat('MMM yyyy');
final DateFormat dayHeaderFormat = DateFormat('EEE, d MMM');
final DateFormat fullDateFormat = DateFormat('d MMM yyyy');
final DateFormat timeFormat = DateFormat('h:mm a');
