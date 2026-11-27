import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/models/category.dart';
import '../../data/models/recurring_rule.dart';
import '../../data/models/txn.dart';
import '../../services/recurring_engine.dart';
import '../../state/providers.dart';
import '../entry/category_picker.dart';
import '../icons.dart';
import '../widgets/common.dart';

/// Adds or edits a recurring payment and its reminder.
class RecurringFormPage extends ConsumerStatefulWidget {
  const RecurringFormPage({super.key, this.existing});
  final RecurringRule? existing;

  @override
  ConsumerState<RecurringFormPage> createState() => _RecurringFormPageState();
}

class _RecurringFormPageState extends ConsumerState<RecurringFormPage> {
  static const _reminderChoices = {
    -1: 'No reminder',
    0: 'On the day',
    1: '1 day before',
    2: '2 days before',
    3: '3 days before',
    7: '1 week before',
  };

  final _formKey = GlobalKey<FormState>();
  late final _amount = TextEditingController(
    text: widget.existing == null ? '' : paiseToInput(widget.existing!.amount),
  );
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  late final _interval = TextEditingController(text: '${widget.existing?.interval ?? 1}');
  late TxnType _type = widget.existing?.type ?? TxnType.expense;
  late int? _accountId = widget.existing?.accountId;
  late int? _toAccountId = widget.existing?.toAccountId;
  late int? _categoryId = widget.existing?.categoryId;
  late Frequency _frequency = widget.existing?.frequency ?? Frequency.monthly;
  late DateTime _nextDue = widget.existing?.nextDue ?? const RecurringEngine().firstDue(DateTime.now());
  late DateTime? _endDate = widget.existing?.endDate;
  late bool _autoPost = widget.existing?.autoPost ?? false;
  late int _remind = widget.existing?.remindDaysBefore ?? 1;
  late bool _active = widget.existing?.active ?? true;

  @override
  void initState() {
    super.initState();
    if (_accountId == null) {
      ref.read(lookupsProvider.future).then((l) {
        if (mounted) setState(() => _accountId ??= l.defaultAccount?.id);
      });
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _interval.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final existing = widget.existing;
    final startDate = existing == null || existing.nextDue != _nextDue ? _nextDue : existing.startDate;
    final rule = RecurringRule(
      id: existing?.id,
      type: _type,
      amount: parseMoney(_amount.text)!,
      accountId: _accountId!,
      categoryId: _type == TxnType.transfer ? null : _categoryId,
      toAccountId: _type == TxnType.transfer ? _toAccountId : null,
      note: _note.text.trim(),
      frequency: _frequency,
      interval: int.tryParse(_interval.text) ?? 1,
      startDate: startDate,
      endDate: _endDate,
      nextDue: _nextDue,
      autoPost: _autoPost,
      remindDaysBefore: _remind,
      active: _active,
    );
    await ref.read(actionsProvider).saveRule(rule);
    if (_remind >= 0) await ref.read(reminderServiceProvider).requestPermission();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this recurring payment?'),
        content: const Text('Entries already recorded stay. Future reminders stop.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(actionsProvider).deleteRule(widget.existing!.id!);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final lookups = ref.watch(lookupsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'New recurring payment' : 'Recurring payment'),
        actions: [
          if (widget.existing != null)
            IconButton(tooltip: 'Delete', icon: const AppIcon(AppIcons.delete), onPressed: _delete),
        ],
      ),
      body: AsyncBody(
        value: lookups,
        builder: (l) {
          final accounts = l.activeAccounts;
          final kind = _type == TxnType.income ? CategoryKind.income : CategoryKind.expense;
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SegmentedButton<TxnType>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: TxnType.income, label: Text('Income')),
                    ButtonSegment(value: TxnType.expense, label: Text('Expense')),
                    ButtonSegment(value: TxnType.transfer, label: Text('Transfer')),
                  ],
                  selected: {_type},
                  onSelectionChanged: (s) => setState(() {
                    _type = s.first;
                    _categoryId = null;
                  }),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ '),
                  validator: (v) => parseMoney(v ?? '') == null ? 'Enter an amount' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _note,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Name', hintText: 'Room rent, Phone EMI, Salary…'),
                ),
                const SizedBox(height: 12),
                if (_type != TxnType.transfer) ...[
                  FormField<int>(
                    validator: (_) => _categoryId == null ? 'Pick a category' : null,
                    builder: (field) => InkWell(
                      onTap: () async {
                        final c = await showCategoryPicker(context, l.activeCategories(kind), selectedId: _categoryId);
                        if (c != null) setState(() => _categoryId = c.id);
                        field.didChange(_categoryId);
                      },
                      child: InputDecorator(
                        decoration: InputDecoration(labelText: 'Category', errorText: field.errorText),
                        child: Text(l.categoryById[_categoryId]?.label ?? 'Choose'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                DropdownButtonFormField<int>(
                  icon: const AppIcon(AppIcons.dropDown, size: 20),
                  isExpanded: true,
                  style: Theme.of(context).textTheme.bodyLarge,
                  key: ValueKey('acc-$_accountId'),
                  initialValue: _accountId,
                  decoration: InputDecoration(labelText: _type == TxnType.transfer ? 'From account' : 'Account'),
                  items: [for (final a in accounts) DropdownMenuItem(value: a.id, child: Text(a.name))],
                  onChanged: (v) => setState(() => _accountId = v),
                  validator: (v) => v == null ? 'Pick an account' : null,
                ),
                if (_type == TxnType.transfer) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    icon: const AppIcon(AppIcons.dropDown, size: 20),
                    isExpanded: true,
                    style: Theme.of(context).textTheme.bodyLarge,
                    initialValue: _toAccountId,
                    decoration: const InputDecoration(labelText: 'To account'),
                    items: [for (final a in accounts) DropdownMenuItem(value: a.id, child: Text(a.name))],
                    onChanged: (v) => setState(() => _toAccountId = v),
                    validator: (v) => v == null || v == _accountId ? 'Pick a different account' : null,
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    SizedBox(
                      width: 90,
                      child: TextFormField(
                        controller: _interval,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Every'),
                        validator: (v) => (int.tryParse(v ?? '') ?? 0) < 1 ? '1 or more' : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<Frequency>(
                        icon: const AppIcon(AppIcons.dropDown, size: 20),
                        isExpanded: true,
                        style: Theme.of(context).textTheme.bodyLarge,
                        initialValue: _frequency,
                        decoration: const InputDecoration(labelText: 'Repeats'),
                        items: [
                          for (final f in Frequency.values) DropdownMenuItem(value: f, child: Text('${f.unit}(s)')),
                        ],
                        onChanged: (v) => setState(() => _frequency = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const AppIcon(AppIcons.calendar),
                  title: const Text('Next due'),
                  subtitle: Text(fullDateFormat.format(_nextDue)),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _nextDue,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (d != null) setState(() => _nextDue = DateTime(d.year, d.month, d.day, 9));
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const AppIcon(AppIcons.calendarEnd),
                  title: const Text('Ends'),
                  subtitle: Text(_endDate == null ? 'Never' : fullDateFormat.format(_endDate!)),
                  trailing: _endDate == null
                      ? null
                      : IconButton(
                          icon: const AppIcon(AppIcons.close),
                          onPressed: () => setState(() => _endDate = null),
                        ),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _endDate ?? _nextDue,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (d != null) setState(() => _endDate = d);
                  },
                ),
                DropdownButtonFormField<int>(
                  icon: const AppIcon(AppIcons.dropDown, size: 20),
                  isExpanded: true,
                  style: Theme.of(context).textTheme.bodyLarge,
                  initialValue: _reminderChoices.containsKey(_remind) ? _remind : 1,
                  decoration: const InputDecoration(labelText: 'Reminder', prefixIcon: AppIcon(AppIcons.notification)),
                  items: [
                    for (final e in _reminderChoices.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() => _remind = v!),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Record automatically'),
                  subtitle: const Text(
                    'Off: it waits under "Due now" until you confirm you paid. '
                    'On: it is recorded by itself on the due date.',
                  ),
                  value: _autoPost,
                  onChanged: (v) => setState(() => _autoPost = v),
                ),
                if (widget.existing != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Active'),
                    value: _active,
                    onChanged: (v) => setState(() => _active = v),
                  ),
                const SizedBox(height: 24),
                FilledButton(onPressed: _save, child: const Text('Save')),
              ],
            ),
          );
        },
      ),
    );
  }
}
