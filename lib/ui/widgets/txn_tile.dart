import 'package:material_ui/material_ui.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/models/txn.dart';
import '../../state/providers.dart';
import '../entry/transaction_form_page.dart';
import '../icons.dart';
import '../theme.dart';
import 'common.dart';

/// One entry in a list: category, note, account and signed amount.
class TxnTile extends StatelessWidget {
  const TxnTile({super.key, required this.txn, required this.lookups, this.showDate = false});

  final Txn txn;
  final Lookups lookups;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final category = lookups.categoryById[txn.categoryId];
    final account = lookups.accountById[txn.accountId]?.name ?? '?';
    final String title;
    final String subtitle;
    final Widget leading;
    if (txn.type == TxnType.transfer) {
      final to = lookups.accountById[txn.toAccountId]?.name ?? '?';
      title = txn.note.isNotEmpty ? txn.note : 'Transfer';
      subtitle = '$account → $to';
      leading = EmojiAvatar(emoji: '⇄', color: MoneyColors.neutral(context));
    } else {
      title = txn.note.isNotEmpty ? txn.note : (category?.name ?? 'Uncategorised');
      subtitle = '${category?.name ?? 'Uncategorised'} · $account';
      leading = EmojiAvatar(emoji: category?.icon ?? '•', color: Color(category?.color ?? 0xFF9E9E9E));
    }
    final sign = switch (txn.type) {
      TxnType.income => '+',
      TxnType.expense => '-',
      TxnType.transfer => '',
    };
    return ListTile(
      leading: leading,
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Row(
        children: [
          Flexible(
            child: Text(
              showDate ? '${fullDateFormat.format(txn.date)} · $subtitle' : subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ..._sourceIcons(context),
        ],
      ),
      trailing: Text(
        '$sign${formatMoney(txn.amount)}',
        style: Theme.of(context).textTheme.titleSmall?.copyWith(color: MoneyColors.forType(context, txn.type)),
      ),
      onTap: () =>
          Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TransactionFormPage(existing: txn))),
    );
  }

  List<Widget> _sourceIcons(BuildContext context) {
    final icon = switch (txn.source) {
      TxnSource.screenshot => AppIcons.screenshot,
      TxnSource.voice => AppIcons.mic,
      TxnSource.recurring => AppIcons.repeat,
      TxnSource.imported => AppIcons.upload,
      TxnSource.notification => AppIcons.notification,
      TxnSource.manual => null,
    };
    if (icon == null) return const [];
    return [const SizedBox(width: 6), AppIcon(icon, size: 14, color: Theme.of(context).colorScheme.primary)];
  }
}
