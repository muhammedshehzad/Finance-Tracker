import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/models/txn.dart';
import '../../state/providers.dart';
import '../icons.dart';
import '../motion.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/txn_tile.dart';

/// The selected month's entries, grouped by day.
class DailyView extends ConsumerWidget {
  const DailyView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final summary = ref.watch(monthSummaryProvider(month));
    final txns = ref.watch(monthTxnsProvider);
    final lookups = ref.watch(lookupsProvider);

    return Column(
      children: [
        summary.maybeWhen(
          data: (s) => SummaryRow(income: s.income, expense: s.expense),
          orElse: () => const SizedBox(height: 64),
        ),
        const Divider(height: 1),
        Expanded(
          child: AsyncBody(
            value: txns,
            builder: (list) => AsyncBody(
              value: lookups,
              builder: (l) {
                if (list.isEmpty) {
                  return const EmptyState(
                    icon: AppIcons.note,
                    message: 'Nothing recorded this month.\nTap + to add, or use the mic or a payment screenshot.',
                  );
                }
                return DayGroupedList(txns: list, lookups: l);
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Transactions grouped under a header per day with that day's totals.
class DayGroupedList extends StatelessWidget {
  const DayGroupedList({super.key, required this.txns, required this.lookups, this.padBottom = true});

  final List<Txn> txns;
  final Lookups lookups;
  final bool padBottom;

  @override
  Widget build(BuildContext context) {
    final groups = <DateTime, List<Txn>>{};
    for (final t in txns) {
      groups.putIfAbsent(startOfDay(t.date), () => []).add(t);
    }
    final days = groups.keys.toList()..sort((a, b) => b.compareTo(a));
    return ListView.builder(
      padding: EdgeInsets.only(bottom: padBottom ? 160 : 16),
      itemCount: days.length,
      itemBuilder: (context, i) {
        final day = days[i];
        final items = groups[day]!;
        var income = 0;
        var expense = 0;
        for (final t in items) {
          if (t.type == TxnType.income) income += t.amount;
          if (t.type == TxnType.expense) expense += t.amount;
        }
        final group = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(dayHeaderFormat.format(day), style: Theme.of(context).textTheme.titleSmall),
                  const Spacer(),
                  if (income > 0) Text(formatMoney(income), style: TextStyle(color: MoneyColors.income(context))),
                  if (income > 0 && expense > 0) const SizedBox(width: 12),
                  if (expense > 0) Text(formatMoney(expense), style: TextStyle(color: MoneyColors.expense(context))),
                ],
              ),
            ),
            for (final t in items) TxnTile(txn: t, lookups: lookups),
          ],
        );
        // The first screenful arrives one day after another; the rest as is.
        return i < 6
            ? FadeIn(
                delay: Duration(milliseconds: 40 * i),
                child: group,
              )
            : group;
      },
    );
  }
}
