import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../state/providers.dart';
import '../entry/transaction_form_page.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'daily_view.dart';

/// The selected month as a calendar with daily totals.
class CalendarView extends ConsumerWidget {
  const CalendarView({super.key});

  static const _weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final summary = ref.watch(monthSummaryProvider(month));
    final daily = ref.watch(dailySummariesProvider);
    final today = DateTime.now();
    final leadingSundayFirstBlanks = DateTime(month.year, month.month, 1).weekday % 7;
    final days = daysInMonth(month.year, month.month);
    final cells = leadingSundayFirstBlanks + days;
    final rows = (cells / 7).ceil();

    return Column(
      children: [
        summary.maybeWhen(
          data: (s) => SummaryRow(income: s.income, expense: s.expense),
          orElse: () => const SizedBox(height: 64),
        ),
        const Divider(height: 1),
        Row(
          children: [
            for (final (i, d) in _weekdays.indexed)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    d,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: i == 0 ? MoneyColors.expense(context) : MoneyColors.neutral(context),
                    ),
                  ),
                ),
              ),
          ],
        ),
        Expanded(
          child: AsyncBody(
            value: daily,
            builder: (data) => LayoutBuilder(
              builder: (context, constraints) {
                final cellHeight = (constraints.maxHeight - 80) / rows;
                return GridView.builder(
                  padding: const EdgeInsets.only(bottom: 80),
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisExtent: cellHeight.clamp(56, 120),
                  ),
                  itemCount: rows * 7,
                  itemBuilder: (context, i) {
                    final day = i - leadingSundayFirstBlanks + 1;
                    if (day < 1 || day > days) return const SizedBox.shrink();
                    final s = data[day];
                    final date = DateTime(month.year, month.month, day);
                    final isToday = isSameDay(date, today);
                    return InkWell(
                      onTap: () => _openDay(context, ref, date),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.3), width: 0.5),
                          color: isToday ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5) : null,
                        ),
                        padding: const EdgeInsets.all(3),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('$day', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            const Spacer(),
                            if (s != null && s.income > 0) _amount(context, s.income, MoneyColors.income(context)),
                            if (s != null && s.expense > 0) _amount(context, s.expense, MoneyColors.expense(context)),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _amount(BuildContext context, int paise, Color color) => Align(
    alignment: Alignment.centerRight,
    child: FittedBox(
      child: Text(formatMoney(paise, symbol: false), style: TextStyle(fontSize: 11, color: color)),
    ),
  );

  Future<void> _openDay(BuildContext context, WidgetRef ref, DateTime day) async {
    final repo = ref.read(repositoryProvider);
    final lookups = await ref.read(lookupsProvider.future);
    final txns = await repo.txnsBetween(day, DateTime(day.year, day.month, day.day + 1));
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            ListTile(
              title: Text(fullDateFormat.format(day), style: Theme.of(context).textTheme.titleMedium),
              trailing: FilledButton.tonalIcon(
                icon: const Icon(Icons.add),
                label: const Text('Add'),
                onPressed: () {
                  Navigator.of(context).pop();
                  final now = DateTime.now();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => TransactionFormPage(
                        initialDate: DateTime(day.year, day.month, day.day, now.hour, now.minute),
                      ),
                    ),
                  );
                },
              ),
            ),
            Expanded(
              child: txns.isEmpty
                  ? const EmptyState(icon: Icons.event_available, message: 'Nothing recorded on this day.')
                  : DayGroupedList(txns: txns, lookups: lookups, padBottom: false),
            ),
          ],
        ),
      ),
    );
  }
}
