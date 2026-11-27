import 'dart:developer';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/dates.dart';
import '../../state/providers.dart';
import '../icons.dart';
import '../motion.dart';
import '../theme.dart';

/// "< Nov 2026 >" switcher bound to the selected month.
class MonthSwitcher extends ConsumerWidget {
  const MonthSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final notifier = ref.read(selectedMonthProvider.notifier);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(tooltip: 'Previous month', icon: const AppIcon(AppIcons.previous), onPressed: notifier.previous),
        GestureDetector(
          onTap: () => notifier.set(DateTime.now()),
          child: SwapIn(
            value: month,
            child: Text(monthYearFormat.format(month), style: Theme.of(context).textTheme.titleMedium),
          ),
        ),
        IconButton(tooltip: 'Next month', icon: const AppIcon(AppIcons.next), onPressed: notifier.next),
      ],
    );
  }
}

/// Income / Expenses / Net row shown above lists.
class SummaryRow extends StatelessWidget {
  const SummaryRow({super.key, required this.income, required this.expense, this.netLabel = 'Net'});

  final int income;
  final int expense;
  final String netLabel;

  @override
  Widget build(BuildContext context) {
    final net = income - expense;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Row(
        children: [
          _cell(context, 'Income', income, MoneyColors.income(context)),
          _cell(context, 'Expenses', expense, MoneyColors.expense(context)),
          _cell(context, netLabel, net, MoneyColors.forSigned(context, net)),
        ],
      ),
    );
  }

  Widget _cell(BuildContext context, String label, int value, Color color) => Expanded(
    child: Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        FittedBox(
          child: AnimatedMoney(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color)),
        ),
      ],
    ),
  );
}

/// Renders an AsyncValue with the app's loader, and fades the content in
/// once it arrives. A refresh keeps the old content on screen.
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({super.key, required this.value, required this.builder});

  final AsyncValue<T> value;
  final Widget Function(T data) builder;

  @override
  Widget build(BuildContext context) {
    final child = value.when(
      data: (data) => KeyedSubtree(key: const ValueKey('data'), child: builder(data)),
      loading: () => const AppLoader(key: ValueKey('loading')),
      error: (e, st) {
        log('Screen failed to load', error: e, stackTrace: st);
        return const Center(
          key: ValueKey('error'),
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('This screen couldn\'t load. Go back and open it again.', textAlign: TextAlign.center),
          ),
        );
      },
    );
    return AnimatedSwitcher(
      duration: Motion.of(context, Motion.medium),
      switchInCurve: Motion.curve,
      switchOutCurve: Curves.easeIn,
      child: child,
    );
  }
}

/// A centred icon and message for a screen with nothing to show.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message});
  final AppIconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: FadeIn(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(icon, size: 48, color: color),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// A small circular badge with an emoji, used for categories.
class EmojiAvatar extends StatelessWidget {
  const EmojiAvatar({super.key, required this.emoji, required this.color, this.size = 40});
  final String emoji;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.18), shape: BoxShape.circle),
      child: Text(emoji, style: TextStyle(fontSize: size * 0.48)),
    );
  }
}
