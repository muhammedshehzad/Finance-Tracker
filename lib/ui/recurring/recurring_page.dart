import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/models/recurring_rule.dart';
import '../../data/models/txn.dart';
import '../../services/recurring_engine.dart';
import '../../state/providers.dart';
import '../entry/transaction_form_page.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'recurring_form_page.dart';

/// Recurring payments, with what is due now on top.
class RecurringPage extends ConsumerWidget {
  const RecurringPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(recurringRulesProvider);
    final lookups = ref.watch(lookupsProvider);
    const engine = RecurringEngine();
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(title: const Text('Recurring payments')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add recurring payment',
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const RecurringFormPage())),
        child: const AppIcon(AppIcons.add),
      ),
      body: AsyncBody(
        value: rules,
        builder: (all) => AsyncBody(
          value: lookups,
          builder: (l) {
            if (all.isEmpty) {
              return const EmptyState(
                icon: AppIcons.recurring,
                message: 'No recurring payments yet.\nAdd rent, EMIs or salary and get a reminder before each one.',
              );
            }
            final due = all.where((r) => !r.autoPost && engine.isDue(r, now)).toList();
            final upcoming = all.where((r) => r.active && !due.contains(r)).toList();
            final ended = all.where((r) => !r.active).toList();

            String title(RecurringRule r) {
              if (r.note.isNotEmpty) return r.note;
              if (r.type == TxnType.transfer) return 'Transfer to ${l.accountById[r.toAccountId]?.name ?? '?'}';
              return l.categoryById[r.categoryId]?.name ?? 'Payment';
            }

            return ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                if (due.isNotEmpty) ...[
                  _header(context, 'Due now'),
                  for (final r in due)
                    Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          children: [
                            ListTile(
                              title: Text(title(r)),
                              subtitle: Text(
                                'Due ${fullDateFormat.format(r.nextDue)} · ${l.accountById[r.accountId]?.name ?? ''}',
                              ),
                              trailing: Text(
                                formatMoney(r.amount),
                                style: TextStyle(
                                  color: MoneyColors.forType(context, r.type),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () => ref.read(actionsProvider).skipRule(r),
                                  child: const Text('Skip'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.of(context)
                                      .push(MaterialPageRoute<void>(builder: (_) => TransactionFormPage(fromRule: r))),
                                  child: const Text('Edit & record'),
                                ),
                                const SizedBox(width: 4),
                                FilledButton(
                                  onPressed: () async {
                                    await ref.read(actionsProvider).recordRule(r);
                                    if (context.mounted) showSnack(context, 'Recorded ${title(r)}');
                                  },
                                  child: const Text('Record'),
                                ),
                                const SizedBox(width: 12),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
                if (upcoming.isNotEmpty) ...[
                  _header(context, 'Upcoming'),
                  for (final r in upcoming) _ruleTile(context, r, title(r)),
                ],
                if (ended.isNotEmpty) ...[
                  _header(context, 'Paused or ended'),
                  for (final r in ended) _ruleTile(context, r, title(r)),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(text, style: Theme.of(context).textTheme.labelLarge),
  );

  Widget _ruleTile(BuildContext context, RecurringRule r, String title) {
    final details = [
      r.scheduleLabel,
      if (r.active) 'next ${fullDateFormat.format(r.nextDue)}',
      if (r.autoPost) 'records itself',
    ].join(' · ');
    return ListTile(
      leading: AppIcon(r.active ? AppIcons.recurring : AppIcons.paused),
      title: Text(title),
      subtitle: Text(details),
      trailing: Text(formatMoney(r.amount), style: TextStyle(color: MoneyColors.forType(context, r.type))),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RecurringFormPage(existing: r))),
    );
  }
}
