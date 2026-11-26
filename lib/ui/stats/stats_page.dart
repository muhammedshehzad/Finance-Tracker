import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/models/category.dart';
import '../../data/models/txn.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/txn_tile.dart';

/// Spending or income by category for the selected month.
class StatsPage extends ConsumerStatefulWidget {
  const StatsPage({super.key});

  @override
  ConsumerState<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends ConsumerState<StatsPage> {
  TxnType _type = TxnType.expense;

  @override
  Widget build(BuildContext context) {
    final month = ref.watch(selectedMonthProvider);
    final totals = ref.watch(categoryTotalsProvider((month, _type)));
    final lookups = ref.watch(lookupsProvider);

    return Scaffold(
      appBar: AppBar(title: const MonthSwitcher(), centerTitle: false),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<TxnType>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: TxnType.expense, label: Text('Expenses')),
                ButtonSegment(value: TxnType.income, label: Text('Income')),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
          ),
          Expanded(
            child: AsyncBody(
              value: totals,
              builder: (t) => AsyncBody(
                value: lookups,
                builder: (l) {
                  if (t.isEmpty) {
                    return const EmptyState(icon: Icons.pie_chart_outline, message: 'Nothing recorded for this month.');
                  }
                  final sum = t.fold<int>(0, (s, c) => s + c.total);
                  final slices = [
                    for (final c in t)
                      _Slice(value: c.total, color: Color(l.categoryById[c.categoryId]?.color ?? 0xFF9E9E9E)),
                  ];
                  return ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      SizedBox(
                        height: 220,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CustomPaint(size: const Size(200, 200), painter: _DonutPainter(slices)),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _type == TxnType.expense ? 'Spent' : 'Received',
                                  style: Theme.of(context).textTheme.labelMedium,
                                ),
                                Text(formatMoney(sum), style: Theme.of(context).textTheme.titleLarge),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final c in t)
                        _CategoryShareTile(
                          category: l.categoryById[c.categoryId],
                          total: c.total,
                          share: c.total / sum,
                          onTap: c.categoryId == null
                              ? null
                              : () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => CategoryMonthPage(categoryId: c.categoryId!, month: month),
                                  ),
                                ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryShareTile extends StatelessWidget {
  const _CategoryShareTile({required this.category, required this.total, required this.share, this.onTap});

  final Category? category;
  final int total;
  final double share;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = Color(category?.color ?? 0xFF9E9E9E);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            EmojiAvatar(emoji: category?.icon ?? '•', color: color),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          category?.name ?? 'Uncategorised',
                          style: theme.textTheme.bodyLarge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(formatMoney(total), style: theme.textTheme.titleSmall),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: share,
                            minHeight: 4,
                            color: color,
                            backgroundColor: theme.colorScheme.surfaceContainerHighest,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 44,
                        child: Text(
                          '${(share * 100).round()}%',
                          textAlign: TextAlign.end,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Slice {
  const _Slice({required this.value, required this.color});
  final int value;
  final Color color;
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.slices);
  final List<_Slice> slices;

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<int>(0, (s, x) => s + x.value);
    if (total == 0) return;
    const stroke = 22.0;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: size.shortestSide / 2 - stroke / 2);
    var start = -math.pi / 2;
    for (final s in slices) {
      final sweep = 2 * math.pi * s.value / total;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = s.color;
      canvas.drawArc(rect, start, math.max(sweep - 0.01, 0.001), false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.slices != slices;
}

/// All entries of one category in one month.
class CategoryMonthPage extends ConsumerWidget {
  const CategoryMonthPage({super.key, required this.categoryId, required this.month});
  final int categoryId;
  final DateTime month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lookups = ref.watch(lookupsProvider);
    final txnsValue = ref.watch(categoryMonthTxnsProvider((categoryId, month)));
    return Scaffold(
      appBar: AppBar(
        title: Text('${lookups.asData?.value.categoryById[categoryId]?.name ?? ''} · ${monthYearFormat.format(month)}'),
      ),
      body: AsyncBody(
        value: txnsValue,
        builder: (txns) {
          final l = lookups.asData?.value;
          if (l == null) return const Center(child: CircularProgressIndicator());
          return ListView.builder(
            itemCount: txns.length,
            itemBuilder: (_, i) => TxnTile(txn: txns[i], lookups: l, showDate: true),
          );
        },
      ),
    );
  }
}
