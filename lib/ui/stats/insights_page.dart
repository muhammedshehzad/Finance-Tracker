import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/dates.dart';
import '../../services/insights_service.dart';
import '../../state/providers.dart';
import '../icons.dart';
import '../motion.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'stats_page.dart';

/// The icon for an insight.
AppIconData insightIcon(Insight i) => switch (i.kind) {
  InsightKind.pace => i.tone == InsightTone.good ? AppIcons.down : AppIcons.up,
  InsightKind.categoryUp => AppIcons.up,
  InsightKind.categoryDown => AppIcons.down,
  InsightKind.savings => AppIcons.budget,
  InsightKind.daily => AppIcons.calendarDay,
  InsightKind.biggest => AppIcons.transactions,
  InsightKind.payee => AppIcons.person,
};

/// The colour for an insight's tone.
Color insightColor(BuildContext context, InsightTone tone) => switch (tone) {
  InsightTone.good => MoneyColors.income(context),
  InsightTone.bad => MoneyColors.expense(context),
  InsightTone.neutral => Theme.of(context).colorScheme.primary,
};

/// Everything a month's entries show, compared with the month before.
class InsightsPage extends ConsumerWidget {
  const InsightsPage({super.key, required this.month});

  final DateTime month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: Text('${monthYearFormat.format(month)} insights')),
      body: AsyncBody(
        value: ref.watch(insightsProvider(month)),
        builder: (m) {
          if (m.items.isEmpty) {
            return const EmptyState(
              icon: AppIcons.insights,
              message: 'Add a few entries this month and last, and what changed shows here.',
            );
          }
          final previous = DateTime(month.year, month.month - 1);
          return ListView(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
            children: [
              for (final (i, item) in m.items.indexed)
                FadeIn(
                  delay: Duration(milliseconds: 40 * i),
                  child: Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: insightColor(context, item.tone).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: AppIcon(insightIcon(item), size: 20, color: insightColor(context, item.tone)),
                      ),
                      title: Text(item.title),
                      subtitle: Padding(padding: const EdgeInsets.only(top: 2), child: Text(item.detail)),
                      trailing: item.categoryId == null ? null : const AppIcon(AppIcons.next, size: 20),
                      onTap: item.categoryId == null
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => CategoryMonthPage(categoryId: item.categoryId!, month: month),
                              ),
                            ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Text(
                  m.comparedThroughDay == null
                      ? 'Compared with all of ${monthYearFormat.format(previous)}. Transfers aren\'t counted.'
                      : 'Compared with the same days of ${monthYearFormat.format(previous)}, 1 to '
                            '${m.comparedThroughDay!.clamp(1, daysInMonth(previous.year, previous.month))}, so a month '
                            'in progress is fair to the one before. Transfers aren\'t counted.',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The month's main insight, at the top of Stats, leading to the rest.
class InsightsCard extends ConsumerWidget {
  const InsightsCard({super.key, required this.month});

  final DateTime month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(insightsProvider(month)).value;
    final headline = m?.headline;
    final theme = Theme.of(context);
    return AnimatedSize(
      duration: Motion.of(context, Motion.medium),
      curve: Motion.curve,
      alignment: Alignment.topCenter,
      child: headline == null
          ? const SizedBox(width: double.infinity)
          : Card.filled(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () =>
                    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => InsightsPage(month: month))),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                  child: Row(
                    children: [
                      AppIcon(AppIcons.insights, color: theme.colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SwapIn(
                          alignment: Alignment.centerLeft,
                          value: headline.title,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(headline.title, style: theme.textTheme.titleSmall),
                              const SizedBox(height: 2),
                              Text(
                                m!.items.length > 1
                                    ? '${m.items.length - 1} more ${m.items.length == 2 ? 'insight' : 'insights'} for '
                                          '${monthYearFormat.format(month)}'
                                    : headline.detail,
                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const AppIcon(AppIcons.next, size: 20),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
