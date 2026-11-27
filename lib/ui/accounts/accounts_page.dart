import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/money.dart';
import '../../data/finance_repository.dart';
import '../../data/models/account.dart';
import '../../state/providers.dart';
import '../icons.dart';
import '../motion.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/txn_tile.dart';
import 'account_form_page.dart';

/// Every account with its balance, grouped by kind, and net worth on top.
class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lookups = ref.watch(lookupsProvider);
    final balances = ref.watch(balancesProvider);
    final worth = ref.watch(netWorthProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Accounts')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add account',
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccountFormPage())),
        child: const AppIcon(AppIcons.add),
      ),
      body: AsyncBody(
        value: lookups,
        builder: (l) => AsyncBody(
          value: balances,
          builder: (b) {
            final accounts = l.activeAccounts;
            final noOpening = accounts.every((a) => a.openingBalance == 0);
            return ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                worth.maybeWhen(
                  data: (w) => _NetWorthHeader(worth: w),
                  orElse: () => const SizedBox(height: 140),
                ),
                if (noOpening)
                  const Card(
                    margin: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: ListTile(
                      leading: AppIcon(AppIcons.info),
                      title: Text('Set opening balances'),
                      subtitle: Text(
                        'Tap each account and enter what it held on the day you started. '
                        'Without it, balances only show the change since then.',
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                for (final kind in AccountKind.values)
                  for (final a in accounts.where((a) => a.kind == kind))
                    _AccountTile(account: a, balance: b[a.id] ?? 0),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NetWorthHeader extends StatelessWidget {
  const _NetWorthHeader({required this.worth});
  final NetWorth worth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    Widget cell(String label, int value, Color color) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelMedium?.copyWith(color: muted)),
          const SizedBox(height: 2),
          AnimatedMoney(value, style: theme.textTheme.titleMedium?.copyWith(color: color)),
        ],
      ),
    );
    return Card.filled(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Net worth', style: theme.textTheme.labelLarge?.copyWith(color: muted)),
            const SizedBox(height: 4),
            FittedBox(
              child: AnimatedMoney(
                worth.net,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: worth.net < 0 ? MoneyColors.expense(context) : null,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                cell('Assets', worth.assets, theme.colorScheme.onSurface),
                cell(
                  'Liabilities',
                  worth.liabilities,
                  worth.liabilities > 0 ? MoneyColors.expense(context) : theme.colorScheme.onSurface,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.account, required this.balance});
  final Account account;
  final int balance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = <String>[if (account.kind.label.toLowerCase() != account.name.toLowerCase()) account.kind.label];
    final String value;
    Color? color;
    if (account.kind == AccountKind.creditCard) {
      final owed = balance < 0 ? -balance : 0;
      value = owed > 0 ? '${formatMoney(owed)} due' : formatMoney(balance);
      if (owed > 0) color = MoneyColors.expense(context);
      if (account.creditLimit != null) details.add('${formatMoney(account.creditLimit! - owed)} available');
    } else {
      value = formatMoney(balance);
      if (balance < 0) color = MoneyColors.expense(context);
      if (account.kind == AccountKind.receivable) {
        details
          ..clear()
          ..add('Others owe you');
      }
    }
    final icon = switch (account.kind) {
      AccountKind.cash => AppIcons.cash,
      AccountKind.bank => AppIcons.bank,
      AccountKind.wallet => AppIcons.wallet,
      AccountKind.creditCard => AppIcons.creditCard,
      AccountKind.receivable => AppIcons.lent,
    };
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.secondaryContainer,
        foregroundColor: theme.colorScheme.onSecondaryContainer,
        child: AppIcon(icon, size: 20),
      ),
      title: Text(account.name),
      subtitle: details.isEmpty ? null : Text(details.join(' · ')),
      trailing: Text(value, style: theme.textTheme.titleSmall?.copyWith(color: color)),
      onTap: () =>
          Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => AccountDetailPage(accountId: account.id!))),
    );
  }
}

/// Balance and history of one account.
class AccountDetailPage extends ConsumerWidget {
  const AccountDetailPage({super.key, required this.accountId});
  final int accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lookups = ref.watch(lookupsProvider);
    final balances = ref.watch(balancesProvider);
    final txnsValue = ref.watch(accountTxnsProvider(accountId));
    final account = lookups.asData?.value.accountById[accountId];
    return Scaffold(
      appBar: AppBar(
        title: Text(account?.name ?? ''),
        actions: [
          if (account != null)
            IconButton(
              tooltip: 'Edit account',
              icon: const AppIcon(AppIcons.edit),
              onPressed: () =>
                  Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => AccountFormPage(existing: account))),
            ),
        ],
      ),
      body: AsyncBody(
        value: txnsValue,
        builder: (txns) {
          final l = lookups.asData?.value;
          if (l == null || account == null) return const AppLoader();
          final balance = balances.asData?.value[accountId] ?? 0;
          return ListView(
            children: [
              ListTile(
                title: const Text('Balance'),
                subtitle: Text('Opening balance ${formatMoney(account.openingBalance)}'),
                trailing: AnimatedMoney(
                  balance,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(color: MoneyColors.forSigned(context, balance)),
                ),
              ),
              const Divider(),
              if (txns.isEmpty) const EmptyState(icon: AppIcons.history, message: 'No entries in this account yet.'),
              for (final t in txns) TxnTile(txn: t, lookups: l, showDate: true),
            ],
          );
        },
      ),
    );
  }
}
