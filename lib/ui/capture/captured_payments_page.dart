import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/finance_repository.dart';
import '../../data/models/captured_payment.dart';
import '../../data/models/txn.dart';
import '../../services/capture/notification_parser.dart';
import '../../state/providers.dart';
import '../entry/transaction_form_page.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'capture_settings_page.dart';

/// Payments read from notifications. Nothing is recorded until the user
/// taps Add (or saves from Edit).
class CapturedPaymentsPage extends ConsumerWidget {
  const CapturedPaymentsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingCapturesProvider);
    final lookups = ref.watch(lookupsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Captured payments'),
        actions: [
          IconButton(
            tooltip: 'Capture settings',
            icon: const AppIcon(AppIcons.filter),
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CaptureSettingsPage())),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(actionsProvider).syncCaptures(),
        child: AsyncBody(
          value: pending,
          builder: (items) => AsyncBody(
            value: lookups,
            builder: (l) {
              if (items.isEmpty) {
                return ListView(
                  children: const [
                    SizedBox(height: 120),
                    EmptyState(
                      icon: AppIcons.notification,
                      message:
                          'Nothing waiting. Payments from Google Pay, PhonePe, Paytm and BHIM '
                          'notifications show up here for you to add.',
                    ),
                  ],
                );
              }
              final byId = {for (final c in items) c.id: c};
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: items.length + 1,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return Text(
                      'Check each one, then Add. Edit lets you change the category, account or amount first.',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    );
                  }
                  final c = items[i - 1];
                  return _CaptureCard(capture: c, lookups: l, pairedWith: byId[c.possibleDuplicateOf]);
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CaptureCard extends ConsumerWidget {
  const _CaptureCard({required this.capture, required this.lookups, this.pairedWith});
  final CapturedPayment capture;
  final Lookups lookups;
  final CapturedPayment? pairedWith;

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final d = draftFromCapture(capture, lookups);
    final txn = Txn(
      type: d.type,
      amount: d.amount!,
      date: d.date!,
      accountId: d.accountId!,
      categoryId: d.categoryId,
      note: d.note,
      payee: d.payee,
      upiRef: d.upiRef,
      source: TxnSource.notification,
    );
    try {
      await ref.read(actionsProvider).addCapture(capture, txn);
      if (context.mounted) showSnack(context, 'Added ${formatMoney(txn.amount)}');
    } on DuplicatePaymentException {
      await ref.read(actionsProvider).setCaptureStatus(capture, CaptureStatus.duplicate);
      if (context.mounted) showSnack(context, 'Already recorded with the same UPI reference');
    }
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TransactionFormPage(
          draft: draftFromCapture(capture, lookups),
          onSaved: (_) => ref.read(actionsProvider).markCaptureAdded(capture),
        ),
      ),
    );
  }

  Future<void> _ignore(BuildContext context, WidgetRef ref) async {
    final actions = ref.read(actionsProvider);
    await actions.setCaptureStatus(capture, CaptureStatus.ignored);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Ignored'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => actions.setCaptureStatus(capture, CaptureStatus.pending),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final income = capture.direction == PaymentDirection.credit;
    final draft = draftFromCapture(capture, lookups);
    final category = lookups.categoryById[draft.categoryId];
    final account = lookups.accountById[draft.accountId];
    final color = income ? MoneyColors.income(context) : MoneyColors.expense(context);
    final paired = pairedWith;

    return Card.outlined(
      shape: outlinedCardShape(context),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        capture.counterparty ?? (income ? 'Money received' : 'Payment'),
                        style: t.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${capture.sourceLabel} · ${dayHeaderFormat.format(capture.postedAt)}, ${DateFormat('h:mm a').format(capture.postedAt)}',
                        style: t.bodySmall?.copyWith(color: muted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${income ? '+' : '−'}${formatMoney(capture.amount)}',
                  style: t.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _Chip(text: category?.label ?? 'No category yet', warn: category == null),
                if (account != null) _Chip(text: account.name),
                if (capture.accountHint != null) _Chip(text: '•• ${capture.accountHint}'),
              ],
            ),
            if (paired != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  AppIcon(AppIcons.info, size: 16, color: scheme.tertiary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'May be the same payment as the ${paired.sourceLabel} one at ${DateFormat('h:mm a').format(paired.postedAt)}.',
                      style: t.bodySmall?.copyWith(color: scheme.tertiary),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 4),
            Row(
              children: [
                TextButton(onPressed: () => _ignore(context, ref), child: const Text('Ignore')),
                const Spacer(),
                OutlinedButton(onPressed: () => _edit(context, ref), child: const Text('Edit')),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: category == null || account == null ? () => _edit(context, ref) : () => _add(context, ref),
                  child: Text(category == null ? 'Choose' : 'Add'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, this.warn = false});
  final String text;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: warn ? scheme.errorContainer.withValues(alpha: 0.5) : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: warn ? scheme.onErrorContainer : scheme.onSurfaceVariant),
      ),
    );
  }
}
