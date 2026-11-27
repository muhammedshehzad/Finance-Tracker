import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/finance_repository.dart';
import '../../data/models/txn.dart';
import '../../state/providers.dart';
import '../budgets/budget_settings_page.dart';
import '../icons.dart';
import '../motion.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Monthly budgets against what was spent, with a marker for how far
/// through the month today is.
class BudgetView extends ConsumerWidget {
  const BudgetView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final budgets = ref.watch(budgetsProvider);
    final totals = ref.watch(categoryTotalsProvider((month, TxnType.expense)));
    final summary = ref.watch(monthSummaryProvider(month));
    final lastMonth = ref.watch(monthSummaryProvider(DateTime(month.year, month.month - 1)));
    final lookups = ref.watch(lookupsProvider);

    final now = DateTime.now();
    final double? todayFraction;
    if (month.year == now.year && month.month == now.month) {
      todayFraction = now.day / daysInMonth(now.year, now.month);
    } else {
      todayFraction = null;
    }

    return AsyncBody(
      value: budgets,
      builder: (b) => AsyncBody(
        value: totals,
        builder: (t) => AsyncBody(
          value: lookups,
          builder: (l) {
            final spentBy = {for (final c in t) c.categoryId: c.total};
            final overall = b[FinanceRepository.overallBudgetKey];
            final totalSpent = summary.asData?.value.expense ?? 0;
            final perCategory = b.entries.where((e) => e.key != FinanceRepository.overallBudgetKey).toList()
              ..sort(
                (x, y) => (l.categoryById[x.key]?.sortOrder ?? 0).compareTo(l.categoryById[y.key]?.sortOrder ?? 0),
              );

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 160),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Budgets',
                        style: Theme.of(context).textTheme.titleLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton.icon(
                      icon: const AppIcon(AppIcons.filter),
                      label: const Text('Set budgets'),
                      onPressed: () =>
                          Navigator.of(context)
                              .push(MaterialPageRoute<void>(builder: (_) => const BudgetSettingsPage())),
                    ),
                  ],
                ),
                if (overall == null && perCategory.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('No budgets yet. Set a monthly limit overall or per category.'),
                  ),
                if (overall != null)
                  BudgetBar(label: 'Total budget', budget: overall, spent: totalSpent, todayFraction: todayFraction),
                for (final e in perCategory)
                  BudgetBar(
                    label: l.categoryById[e.key]?.label ?? 'Deleted category',
                    budget: e.value,
                    spent: spentBy[e.key] ?? 0,
                    todayFraction: todayFraction,
                  ),
                const SizedBox(height: 16),
                if (summary.asData != null && lastMonth.asData != null)
                  _Comparison(this_: summary.asData!.value, last: lastMonth.asData!.value),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Spent against a limit, with an optional marker for how far the month is.
class BudgetBar extends StatelessWidget {
  const BudgetBar({super.key, required this.label, required this.budget, required this.spent, this.todayFraction});

  final String label;
  final int budget;
  final int spent;
  final double? todayFraction;

  @override
  Widget build(BuildContext context) {
    final ratio = budget == 0 ? 0.0 : spent / budget;
    final over = spent > budget;
    final ahead = todayFraction != null && ratio > todayFraction! && !over;
    final color = over ? MoneyColors.expense(context) : (ahead ? Colors.orange : Theme.of(context).colorScheme.primary);
    final left = budget - spent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: Theme.of(context).textTheme.titleSmall)),
              Text(
                '${(ratio * 100).round()}%',
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, c) => Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedBar(value: ratio, height: 12, color: color, backgroundColor: color.withValues(alpha: 0.15)),
                if (todayFraction != null)
                  Positioned(
                    left: c.maxWidth * todayFraction! - 1,
                    top: -3,
                    child: Container(width: 2, height: 18, color: Theme.of(context).colorScheme.onSurface),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${formatMoney(spent)} of ${formatMoney(budget)}',
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                over ? '${formatMoney(-left)} over' : '${formatMoney(left)} left',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: over ? color : null),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Comparison extends StatelessWidget {
  const _Comparison({required this.this_, required this.last});
  final PeriodSummary this_;
  final PeriodSummary last;

  @override
  Widget build(BuildContext context) {
    final String text;
    if (last.expense == 0) {
      text = 'No spending recorded last month to compare with.';
    } else {
      final pct = ((this_.expense / last.expense) * 100).round();
      text = 'Spending is $pct% of last month (${formatMoney(last.expense)}).';
    }
    return Card(
      child: ListTile(leading: const AppIcon(AppIcons.compare), title: Text(text)),
    );
  }
}
