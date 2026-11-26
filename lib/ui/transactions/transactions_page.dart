import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/money.dart';
import '../../services/capture/notification_parser.dart';
import '../../state/providers.dart';
import '../capture/captured_payments_page.dart';
import '../entry/entry_fabs.dart';
import '../recurring/recurring_page.dart';
import '../widgets/common.dart';
import 'budget_view.dart';
import 'calendar_view.dart';
import 'daily_view.dart';
import 'monthly_view.dart';
import 'search_page.dart';

/// The main screen: month picker, totals and the daily, calendar,
/// monthly and budget views.
class TransactionsPage extends ConsumerStatefulWidget {
  const TransactionsPage({super.key});

  @override
  ConsumerState<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends ConsumerState<TransactionsPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const MonthSwitcher(),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SearchPage())),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Daily'),
            Tab(text: 'Calendar'),
            Tab(text: 'Monthly'),
            Tab(text: 'Budget'),
          ],
        ),
      ),
      body: Column(
        children: [
          const _CaptureBanner(),
          const _DueBanner(),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                const DailyView(),
                const CalendarView(),
                MonthlyView(onOpenMonth: () => _tabs.animateTo(0)),
                const BudgetView(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: const EntryFabs(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

/// "2 recurring payments are due" banner, linking to the review screen.
class _DueBanner extends ConsumerWidget {
  const _DueBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final due = ref.watch(dueRecurringProvider).asData?.value ?? const [];
    if (due.isEmpty) return const SizedBox.shrink();
    final total = due.fold<int>(0, (s, r) => s + r.amount);
    final lookups = ref.watch(lookupsProvider).asData?.value;
    final scheme = Theme.of(context).colorScheme;
    final first = due.first;
    final name = first.note.isNotEmpty ? first.note : (lookups?.categoryById[first.categoryId]?.name ?? 'A payment');
    final text = due.length == 1
        ? '$name is due · ${formatMoney(total)}'
        : '${due.length} payments due · ${formatMoney(total)}';
    return Material(
      color: scheme.tertiaryContainer,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const RecurringPage())),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            children: [
              Icon(Icons.event_repeat, size: 20, color: scheme.onTertiaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onTertiaryContainer),
                ),
              ),
              Text(
                'Review',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.onTertiaryContainer),
              ),
              Icon(Icons.chevron_right, color: scheme.onTertiaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}

/// "3 payments captured" strip, linking to the review screen.
class _CaptureBanner extends ConsumerWidget {
  const _CaptureBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(pendingCapturesProvider).asData?.value ?? const [];
    if (items.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final first = items.first;
    final text = items.length == 1
        ? '${formatMoney(first.amount)} ${first.direction == PaymentDirection.credit ? 'from' : 'to'} ${first.counterparty ?? first.sourceLabel}'
        : '${items.length} payments captured';
    return Material(
      color: scheme.secondaryContainer,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CapturedPaymentsPage())),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            children: [
              Icon(Icons.notifications_active_outlined, size: 20, color: scheme.onSecondaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSecondaryContainer),
                ),
              ),
              Text(
                'Review',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.onSecondaryContainer),
              ),
              Icon(Icons.chevron_right, color: scheme.onSecondaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}
