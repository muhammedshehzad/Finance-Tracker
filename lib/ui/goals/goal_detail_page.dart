import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/models/goal.dart';
import '../../state/providers.dart';
import '../icons.dart';
import '../motion.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'goal_card.dart';
import 'goal_form_page.dart';

/// One goal: progress, buttons to put money in or take it out, and the
/// history of both.
class GoalDetailPage extends ConsumerWidget {
  const GoalDetailPage({super.key, required this.goalId});

  final int goalId;

  Future<void> _move(BuildContext context, WidgetRef ref, GoalProgress p, {required bool putIn}) async {
    final entry = await showModalBottomSheet<GoalEntry>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MoneySheet(progress: p, putIn: putIn),
    );
    if (entry == null) return;
    await ref.read(actionsProvider).addGoalEntry(entry);
    await HapticFeedback.lightImpact();
    final after = p.saved + entry.amount;
    if (context.mounted && putIn && after >= p.goal.target && !p.reached) {
      showSnack(context, '${p.goal.name} is reached.');
    }
  }

  Future<void> _menu(BuildContext context, WidgetRef ref, GoalProgress p, String choice) async {
    final actions = ref.read(actionsProvider);
    switch (choice) {
      case 'edit':
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GoalFormPage(existing: p.goal)));
      case 'archive':
        await actions.saveGoal(p.goal.copyWith(archived: !p.goal.archived));
        if (context.mounted) Navigator.of(context).pop();
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Delete ${p.goal.name}?'),
            content: const Text(
              'The goal and its history go. Your accounts and entries don\'t change, since a goal only keeps track.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
            ],
          ),
        );
        if (ok != true || !context.mounted) return;
        Navigator.of(context).pop();
        await actions.deleteGoal(p.goal.id!);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final value = ref.watch(goalProvider(goalId));
    final p = value.value;
    return Scaffold(
      appBar: AppBar(
        title: Text(p?.goal.name ?? ''),
        actions: [
          if (p != null)
            PopupMenuButton<String>(
              icon: const AppIcon(AppIcons.more),
              onSelected: (c) => _menu(context, ref, p, c),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'archive', child: Text(p.goal.archived ? 'Bring back' : 'Archive')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
        ],
      ),
      body: AsyncBody(
        value: value,
        builder: (p) {
          if (p == null) return const SizedBox.shrink();
          final entries = ref.watch(goalEntriesProvider(goalId)).value ?? const <GoalEntry>[];
          final done = MoneyColors.income(context);
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  children: [
                    SizedBox.square(
                      dimension: 168,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: p.fraction),
                        duration: Motion.of(context, Motion.long),
                        curve: Motion.curve,
                        builder: (context, v, child) => Stack(
                          fit: StackFit.expand,
                          children: [
                            CircularProgressIndicator(
                              value: v,
                              strokeWidth: 10,
                              strokeCap: StrokeCap.round,
                              color: p.reached ? done : scheme.primary,
                              backgroundColor: scheme.surfaceContainerHighest,
                            ),
                            child!,
                          ],
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(p.goal.emoji, style: const TextStyle(fontSize: 32)),
                              const SizedBox(height: 4),
                              Text(
                                '${(p.fraction * 100).floor()}%',
                                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    AnimatedMoney(p.saved, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
                    Text(
                      'of ${formatMoney(p.goal.target)}',
                      style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    SwapIn(
                      value: goalLine(p, DateTime.now()),
                      child: Text(
                        goalLine(p, DateTime.now()),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(color: p.reached ? done : null),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => _move(context, ref, p, putIn: true),
                            icon: const AppIcon(AppIcons.putIn, size: 20),
                            label: const Text('Put in'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: p.saved > 0 ? () => _move(context, ref, p, putIn: false) : null,
                            icon: const AppIcon(AppIcons.takeOut, size: 20),
                            label: const Text('Take out'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
                child: Text('History', style: theme.textTheme.titleSmall?.copyWith(color: scheme.primary)),
              ),
              if (entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Nothing put in yet. A goal only keeps track: your account balances don\'t change.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              for (final e in entries)
                Dismissible(
                  key: ValueKey(e.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    color: scheme.errorContainer,
                    child: AppIcon(AppIcons.delete, color: scheme.onErrorContainer),
                  ),
                  onDismissed: (_) {
                    ref.read(actionsProvider).deleteGoalEntry(e.id!);
                    showSnack(context, 'Removed ${formatMoney(e.amount.abs())} from the history.');
                  },
                  child: ListTile(
                    leading: AppIcon(
                      e.amount > 0 ? AppIcons.putIn : AppIcons.takeOut,
                      color: e.amount > 0 ? done : scheme.onSurfaceVariant,
                    ),
                    title: Text(e.note.isEmpty ? (e.amount > 0 ? 'Put in' : 'Taken out') : e.note),
                    subtitle: Text(fullDateFormat.format(e.date)),
                    trailing: Text(
                      formatMoney(e.amount, signed: true),
                      style: theme.textTheme.titleSmall?.copyWith(color: e.amount > 0 ? done : null),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Asks how much to put in or take out, with an optional note.
class _MoneySheet extends StatefulWidget {
  const _MoneySheet({required this.progress, required this.putIn});

  final GoalProgress progress;
  final bool putIn;

  @override
  State<_MoneySheet> createState() => _MoneySheetState();
}

class _MoneySheetState extends State<_MoneySheet> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _done() {
    if (!_formKey.currentState!.validate()) return;
    final paise = parseMoney(_amount.text)!;
    Navigator.of(context).pop(
      GoalEntry(
        goalId: widget.progress.goal.id!,
        amount: widget.putIn ? paise : -paise,
        date: DateTime.now(),
        note: _note.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.progress;
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.putIn ? 'Put money into ${p.goal.name}' : 'Take money out of ${p.goal.name}',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              widget.putIn ? '${formatMoney(p.left)} to go.' : '${formatMoney(p.saved)} is in it now.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ '),
              validator: (v) {
                final paise = parseMoney(v ?? '');
                if (paise == null || paise <= 0) return 'Enter an amount';
                if (!widget.putIn && paise > p.saved) return 'Only ${formatMoney(p.saved)} is in this goal';
                return null;
              },
              onFieldSubmitted: (_) => _done(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
              onSubmitted: (_) => _done(),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _done, child: Text(widget.putIn ? 'Put in' : 'Take out')),
          ],
        ),
      ),
    );
  }
}
