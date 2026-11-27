import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/finance_repository.dart';
import '../../data/models/category.dart';
import '../../data/models/txn.dart';
import '../../services/category_matcher.dart';
import '../../services/receipt_batch.dart';
import '../../services/receipt_parser.dart';
import '../../services/receipt_scanner.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'category_picker.dart';

/// Every payment read from one screenshot, such as a Google Pay history,
/// to tick, fix and save together. Nothing is saved before Save is tapped.
///
/// Payments that look already recorded, failed or are still pending start
/// unticked. One the app has under the same UPI reference can't be ticked.
class MultiReceiptPage extends ConsumerStatefulWidget {
  const MultiReceiptPage({super.key, required this.scanned});

  final ScannedReceipt scanned;

  @override
  ConsumerState<MultiReceiptPage> createState() => _MultiReceiptPageState();
}

class _Row {
  _Row({
    required this.type,
    required this.amount,
    required this.date,
    required this.hasTime,
    required this.payee,
    required this.upiRef,
    required this.app,
    required this.categoryId,
    required this.selected,
    this.locked = false,
  });

  TxnType type;
  int amount;
  DateTime date;
  final bool hasTime;
  String? payee;
  final String? upiRef;
  final String? app;
  int? categoryId;
  bool selected;

  /// Why the row needs a second look, shown under it.
  String? flag;

  /// Already recorded under the same UPI reference.
  final bool locked;
}

class _MultiReceiptPageState extends ConsumerState<MultiReceiptPage> {
  List<_Row>? _rows;
  int? _accountId;
  bool _saving = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (!_saved) ReceiptScanner.deleteStored(widget.scanned.imagePath);
    super.dispose();
  }

  Future<void> _load() async {
    final repo = ref.read(repositoryProvider);
    final lookups = await ref.read(lookupsProvider.future);
    final matcher = CategoryMatcher(lookups.categories);
    final today = startOfDay(DateTime.now());
    final rows = <_Row>[];
    for (final r in widget.scanned.results) {
      final type = r.direction == ReceiptDirection.received ? TxnType.income : TxnType.expense;
      final kind = type == TxnType.income ? CategoryKind.income : CategoryKind.expense;
      final category =
          (r.payee == null ? null : matcher.match(r.payee!, kind)) ?? _fallbackCategory(lookups.activeCategories(kind));
      final row = _Row(
        type: type,
        amount: r.amountPaise!,
        date: r.date ?? today,
        hasTime: r.date != null && r.hasTime,
        payee: r.payee,
        upiRef: r.upiRef,
        app: r.app,
        categoryId: category?.id,
        selected: true,
        locked: r.upiRef != null && await repo.findByUpiRef(r.upiRef!) != null,
      );
      row.flag = await _flagFor(repo, r, row);
      if (row.flag != null && r.date != null) row.selected = false;
      rows.add(row);
    }
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _accountId = lookups.defaultAccount?.id;
    });
  }

  Future<String?> _flagFor(FinanceRepository repo, ReceiptParseResult r, _Row row) async {
    if (row.locked) return 'Already recorded';
    if (r.status == ReceiptStatus.failed) return 'Failed payment';
    if (r.status == ReceiptStatus.pending) return 'Still pending';
    if (r.date == null) return 'No date shown, so it is set to today';
    final day = startOfDay(row.date);
    final sameDay = await repo.txnsBetween(day, day.add(const Duration(days: 1)));
    final match = likelyDuplicate(r, row.type, sameDay);
    if (match == null) return null;
    return 'Looks already recorded: ${formatMoney(match.amount)} on ${fullDateFormat.format(match.date)}';
  }

  static Category? _fallbackCategory(List<Category> categories) {
    for (final c in categories) {
      if (c.name.startsWith('Other')) return c;
    }
    return categories.isEmpty ? null : categories.first;
  }

  Future<void> _edit(_Row row, Lookups lookups) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RowEditor(row: row, lookups: lookups),
    );
    if (changed == true && mounted) setState(() {});
  }

  Future<void> _save() async {
    final picked = _rows!.where((r) => r.selected).toList();
    if (picked.isEmpty || _accountId == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(actionsProvider).saveTxns([
        for (final r in picked)
          Txn(
            type: r.type,
            amount: r.amount,
            date: r.date,
            accountId: _accountId!,
            categoryId: r.categoryId,
            note: r.payee ?? '',
            description: r.app ?? '',
            payee: r.payee,
            upiRef: r.upiRef,
            source: TxnSource.screenshot,
          ),
      ]);
    } on DuplicatePaymentException catch (e) {
      return _saveFailed('$e Untick it and save again.');
    } on ArgumentError catch (e) {
      return _saveFailed('${e.message}');
    }
    _saved = true;
    await ReceiptScanner.deleteStored(widget.scanned.imagePath);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(
      SnackBar(content: Text('Saved ${picked.length} ${picked.length == 1 ? 'entry' : 'entries'}')),
    );
  }

  void _saveFailed(String message) {
    if (!mounted) return;
    setState(() => _saving = false);
    showSnack(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final lookups = ref.watch(lookupsProvider);
    final count = rows?.where((r) => r.selected).length ?? 0;
    return Scaffold(
      appBar: AppBar(title: Text(rows == null ? 'Reading payments…' : '${rows.length} payments found')),
      body: rows == null
          ? const Center(child: CircularProgressIndicator())
          : AsyncBody(
              value: lookups,
              builder: (l) => ListView(
                padding: const EdgeInsets.only(bottom: 16),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: DropdownButtonFormField<int>(
                      initialValue: _accountId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Account for all of them'),
                      items: [for (final a in l.activeAccounts) DropdownMenuItem(value: a.id, child: Text(a.name))],
                      onChanged: (v) => setState(() => _accountId = v),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text(
                      'Tick the ones to save. Tap one to fix it.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  for (final r in rows) _tile(context, r, l),
                ],
              ),
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: count == 0 || _saving || _accountId == null ? null : _save,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(count == 1 ? 'Save 1 entry' : 'Save $count entries'),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, _Row r, Lookups l) {
    final category = r.categoryId == null ? null : l.categoryById[r.categoryId];
    final when = r.hasTime
        ? '${fullDateFormat.format(r.date)}, ${timeFormat.format(r.date)}'
        : fullDateFormat.format(r.date);
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      enabled: !r.locked,
      onTap: () => _edit(r, l),
      leading: Checkbox(value: r.selected, onChanged: r.locked ? null : (v) => setState(() => r.selected = v ?? false)),
      title: Text(r.payee ?? 'Unknown payee', maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$when · ${category?.label ?? 'Pick a category'}'),
          if (r.flag != null) Text(r.flag!, style: TextStyle(color: scheme.error)),
        ],
      ),
      isThreeLine: r.flag != null,
      trailing: Text(
        formatMoney(r.type == TxnType.income ? r.amount : -r.amount, signed: true),
        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: MoneyColors.forType(context, r.type)),
      ),
    );
  }
}

/// Edits one payment's name, amount, direction, category and day.
class _RowEditor extends StatefulWidget {
  const _RowEditor({required this.row, required this.lookups});

  final _Row row;
  final Lookups lookups;

  @override
  State<_RowEditor> createState() => _RowEditorState();
}

class _RowEditorState extends State<_RowEditor> {
  late final _amount = TextEditingController(text: paiseToInput(widget.row.amount));
  late final _payee = TextEditingController(text: widget.row.payee ?? '');
  late TxnType _type = widget.row.type;
  late int? _categoryId = widget.row.categoryId;
  late DateTime _date = widget.row.date;

  @override
  void dispose() {
    _amount.dispose();
    _payee.dispose();
    super.dispose();
  }

  CategoryKind get _kind => _type == TxnType.income ? CategoryKind.income : CategoryKind.expense;

  void _done() {
    final amount = parseMoney(_amount.text);
    if (amount == null || amount <= 0) {
      showSnack(context, 'Enter an amount.');
      return;
    }
    final payee = _payee.text.trim();
    widget.row
      ..payee = payee.isEmpty ? null : payee
      ..amount = amount
      ..type = _type
      ..categoryId = _categoryId
      ..date = _date;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final category = _categoryId == null ? null : widget.lookups.categoryById[_categoryId];
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Edit payment', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          SegmentedButton<TxnType>(
            segments: const [
              ButtonSegment(value: TxnType.expense, label: Text('Paid')),
              ButtonSegment(value: TxnType.income, label: Text('Received')),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() {
              _type = s.first;
              if (category?.kind != _kind) _categoryId = null;
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _payee,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: _type == TxnType.income ? 'Received from' : 'Paid to'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ '),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.category_outlined),
            title: Text(category?.label ?? 'Pick a category'),
            onTap: () async {
              final c = await showCategoryPicker(
                context,
                widget.lookups.activeCategories(_kind),
                selectedId: _categoryId,
              );
              if (c != null) setState(() => _categoryId = c.id);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: Text(fullDateFormat.format(_date)),
            onTap: () async {
              final now = DateTime.now();
              final d = await showDatePicker(
                context: context,
                initialDate: _date.isAfter(now) ? now : _date,
                firstDate: DateTime(2000),
                lastDate: now,
              );
              if (d != null) setState(() => _date = DateTime(d.year, d.month, d.day, _date.hour, _date.minute));
            },
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _categoryId == null ? null : _done, child: const Text('Done')),
        ],
      ),
    );
  }
}
