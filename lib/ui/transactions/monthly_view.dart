import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/money.dart';
import '../../data/finance_repository.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// The selected year month by month. Tapping a month opens it in Daily.
class MonthlyView extends ConsumerWidget {
  const MonthlyView({super.key, required this.onOpenMonth});

  final VoidCallback onOpenMonth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedMonthProvider);
    final year = selected.year;
    final data = ref.watch(yearSummariesProvider(year));
    final now = DateTime.now();
    final monthName = DateFormat('MMMM');

    return AsyncBody(
      value: data,
      builder: (months) {
        final total = months.values.fold(
          PeriodSummary.zero,
          (a, b) => PeriodSummary(income: a.income + b.income, expense: a.expense + b.expense),
        );
        final lastMonth = year == now.year ? now.month : 12;
        return ListView(
          padding: const EdgeInsets.only(bottom: 160),
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Year $year', textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelLarge),
            ),
            SummaryRow(income: total.income, expense: total.expense),
            const Divider(height: 1),
            for (var m = lastMonth; m >= 1; m--)
              if (months[m]!.income > 0 || months[m]!.expense > 0 || (year == now.year && m == now.month))
                ListTile(
                  selected: m == selected.month,
                  title: Text(monthName.format(DateTime(year, m))),
                  subtitle: Text(
                    'In ${formatMoney(months[m]!.income)}  ·  Out ${formatMoney(months[m]!.expense)}',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  trailing: Text(
                    formatMoney(months[m]!.net, signed: true),
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(color: MoneyColors.forSigned(context, months[m]!.net)),
                  ),
                  onTap: () {
                    ref.read(selectedMonthProvider.notifier).set(DateTime(year, m));
                    onOpenMonth();
                  },
                ),
          ],
        );
      },
    );
  }
}
