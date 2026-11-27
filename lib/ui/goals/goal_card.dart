import 'package:material_ui/material_ui.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/models/goal.dart';
import '../motion.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// One goal: its name, how far along it is, and what it needs each month.
class GoalCard extends StatelessWidget {
  const GoalCard({super.key, required this.progress, this.onTap});

  final GoalProgress progress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    final g = progress.goal;
    final done = MoneyColors.income(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  EmojiAvatar(emoji: g.emoji, color: scheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(g.name, style: theme.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(
                          goalLine(progress, DateTime.now()),
                          style: theme.textTheme.bodySmall?.copyWith(color: progress.reached ? done : muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${(progress.fraction * 100).floor()}%',
                    style: theme.textTheme.titleSmall?.copyWith(color: progress.reached ? done : scheme.primary),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              AnimatedBar(
                value: progress.fraction,
                color: progress.reached ? done : scheme.primary,
                backgroundColor: scheme.surfaceContainerHighest,
                height: 8,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  AnimatedMoney(
                    progress.saved,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(' of ${formatMoney(g.target)}', style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The one line under a goal's name: reached, what to put in each month to
/// make the date, that the date has passed, or simply what's left.
String goalLine(GoalProgress p, DateTime now) {
  if (p.reached) return 'Reached';
  final by = p.goal.targetDate;
  final monthly = p.monthlyNeeded(now);
  if (monthly != null) return '${formatMoney(monthly)} a month to reach it by ${monthYearFormat.format(by!)}';
  if (by != null) return '${formatMoney(p.left)} left. The date, ${fullDateFormat.format(by)}, has passed';
  return '${formatMoney(p.left)} to go';
}
