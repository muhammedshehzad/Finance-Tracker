import 'dart:developer';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../services/backup/auto_backup_service.dart';
import '../state/providers.dart';
import 'accounts/accounts_page.dart';
import 'icons.dart';
import 'more/more_page.dart';
import 'motion.dart';
import 'stats/stats_page.dart';
import 'transactions/transactions_page.dart';
import 'widgets/common.dart';

/// The bottom-navigation shell. Runs startup tasks and syncs captured
/// payments whenever the app comes to the front.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  int _index = 0;

  /// Fades the newly picked tab in. Tabs keep their state, so only the
  /// view fades, not the data.
  late final AnimationController _tabFade = AnimationController(vsync: this, value: 1);
  late final _tabOpacity = CurvedAnimation(parent: _tabFade, curve: Motion.curve);
  late final _tabOffset = Tween(begin: const Offset(0, 0.012), end: Offset.zero).animate(_tabOpacity);

  void _select(int i) {
    if (i == _index) return;
    HapticFeedback.selectionClick();
    setState(() => _index = i);
    _tabFade.duration = Motion.of(context, Motion.medium);
    _tabFade.forward(from: 0);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(actionsProvider).syncCaptures();
      final posted = await ref.read(actionsProvider).runStartupTasks();
      if (posted > 0 && mounted) {
        showSnack(context, 'Recorded $posted recurring ${posted == 1 ? 'entry' : 'entries'} that came due');
      }
      await _weeklyBackup();
    });
  }

  /// Saves the weekly backup when it's due, and says so only if it failed.
  Future<void> _weeklyBackup() async {
    var failed = false;
    for (final run in [
      ref.read(autoBackupProvider.notifier).runIfDue,
      ref.read(driveBackupProvider.notifier).runIfDue,
    ]) {
      try {
        await run();
      } on AutoBackupException {
        failed = true;
      } catch (e, st) {
        log('Weekly backup failed', error: e, stackTrace: st);
      }
    }
    if (failed && mounted) showSnack(context, 'This week\'s backup wasn\'t saved. See More → Automatic backup.');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabOpacity.dispose();
    _tabFade.dispose();
    super.dispose();
  }

  /// Payments made while the app was in the background are collected when
  /// it comes back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ref.read(actionsProvider).syncCaptures();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FadeTransition(
        opacity: _tabOpacity,
        child: SlideTransition(
          position: _tabOffset,
          child: IndexedStack(
            index: _index,
            children: const [TransactionsPage(), StatsPage(), AccountsPage(), MorePage()],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        destinations: const [
          NavigationDestination(
            icon: AppIcon(AppIcons.transactions),
            selectedIcon: AppIcon(AppIcons.transactions, strokeWidth: 2.2),
            label: 'Transactions',
          ),
          NavigationDestination(
            icon: AppIcon(AppIcons.stats),
            selectedIcon: AppIcon(AppIcons.stats, strokeWidth: 2.2),
            label: 'Stats',
          ),
          NavigationDestination(
            icon: AppIcon(AppIcons.wallet),
            selectedIcon: AppIcon(AppIcons.wallet, strokeWidth: 2.2),
            label: 'Accounts',
          ),
          NavigationDestination(
            icon: AppIcon(AppIcons.more),
            selectedIcon: AppIcon(AppIcons.more, strokeWidth: 2.2),
            label: 'More',
          ),
        ],
      ),
    );
  }
}
