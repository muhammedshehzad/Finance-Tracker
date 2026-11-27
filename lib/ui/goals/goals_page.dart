import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/money.dart';
import '../../state/providers.dart';
import '../icons.dart';
import '../motion.dart';
import '../widgets/common.dart';
import 'goal_card.dart';
import 'goal_detail_page.dart';
import 'goal_form_page.dart';

/// Every savings goal, with the total set aside on top.
class GoalsPage extends ConsumerStatefulWidget {
  const GoalsPage({super.key});

  @override
  ConsumerState<GoalsPage> createState() => _GoalsPageState();
}

class _GoalsPageState extends ConsumerState<GoalsPage> {
  bool _showArchived = false;

  void _open(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final archived = ref.watch(archivedGoalsProvider).value ?? const [];
    return Scaffold(
      appBar: AppBar(title: const Text('Savings goals')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(const GoalFormPage()),
        icon: const AppIcon(AppIcons.add),
        label: const Text('New goal'),
      ),
      body: AsyncBody(
        value: ref.watch(goalsProvider),
        builder: (goals) {
          if (goals.isEmpty && archived.isEmpty) {
            return const EmptyState(
              icon: AppIcons.goal,
              message: 'Save toward a trip, a phone or an emergency fund. Set an amount, and a date if you like.',
            );
          }
          final saved = goals.fold<int>(0, (sum, g) => sum + g.saved);
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              Card.filled(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Set aside',
                        style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 4),
                      AnimatedMoney(
                        saved,
                        style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        goals.isEmpty
                            ? 'No open goals'
                            : 'Across ${goals.length} ${goals.length == 1 ? 'goal' : 'goals'}, of '
                                  '${formatMoney(goals.fold<int>(0, (sum, g) => sum + g.goal.target))}',
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
              for (final (i, g) in goals.indexed)
                FadeIn(
                  delay: Duration(milliseconds: 40 * i.clamp(0, 6)),
                  child: GoalCard(
                    progress: g,
                    onTap: () => _open(GoalDetailPage(goalId: g.goal.id!)),
                  ),
                ),
              if (archived.isNotEmpty) ...[
                const SizedBox(height: 8),
                ListTile(
                  leading: const AppIcon(AppIcons.archive),
                  title: Text('Archived (${archived.length})'),
                  trailing: AnimatedRotation(
                    turns: _showArchived ? 0.5 : 0,
                    duration: Motion.of(context, Motion.medium),
                    curve: Motion.curve,
                    child: const AppIcon(AppIcons.dropDown, size: 20),
                  ),
                  onTap: () => setState(() => _showArchived = !_showArchived),
                ),
                AnimatedSize(
                  duration: Motion.of(context, Motion.medium),
                  curve: Motion.curve,
                  alignment: Alignment.topCenter,
                  child: _showArchived
                      ? Column(
                          children: [
                            for (final g in archived)
                              GoalCard(
                                progress: g,
                                onTap: () => _open(GoalDetailPage(goalId: g.goal.id!)),
                              ),
                          ],
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
