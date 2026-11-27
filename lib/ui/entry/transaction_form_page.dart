import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/finance_repository.dart';
import '../../data/models/account.dart';
import '../../data/models/category.dart';
import '../../data/models/recurring_rule.dart';
import '../../data/models/txn.dart';
import '../../data/models/txn_draft.dart';
import '../../services/receipt_scanner.dart';
import '../../services/recurring_engine.dart';
import '../../state/providers.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'category_picker.dart';
import 'receipt_entry.dart';

/// Add or edit one income, expense or transfer.
///
/// Also used to confirm entries prefilled from a screenshot or a recurring
/// rule: nothing is stored until Save is tapped.
class TransactionFormPage extends ConsumerStatefulWidget {
  const TransactionFormPage({super.key, this.existing, this.draft, this.initialDate, this.fromRule, this.onSaved});

  final Txn? existing;
  final TxnDraft? draft;
  final DateTime? initialDate;

  /// When set, saving records this occurrence of the rule and moves it on.
  final RecurringRule? fromRule;

  /// Called once the entry is saved, before the page closes.
  final Future<void> Function(Txn saved)? onSaved;

  @override
  ConsumerState<TransactionFormPage> createState() => _TransactionFormPageState();
}

class _TransactionFormPageState extends ConsumerState<TransactionFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _description = TextEditingController();

  TxnType _type = TxnType.expense;
  DateTime _date = DateTime.now();
  int? _accountId;
  int? _toAccountId;
  int? _categoryId;
  String? _payee;
  String? _upiRef;
  String? _attachmentPath;
  String? _originalAttachment;
  TxnSource _source = TxnSource.manual;
  String? _warning;
  Frequency? _repeat;
  bool _saving = false;
  bool _saved = false;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _type = e.type;
      _amount.text = paiseToInput(e.amount);
      _date = e.date;
      _accountId = e.accountId;
      _toAccountId = e.toAccountId;
      _categoryId = e.categoryId;
      _note.text = e.note;
      _description.text = e.description;
      _payee = e.payee;
      _upiRef = e.upiRef;
      _attachmentPath = e.attachmentPath;
      _originalAttachment = e.attachmentPath;
      _source = e.source;
    } else {
      if (widget.initialDate != null) _date = widget.initialDate!;
      final rule = widget.fromRule;
      if (rule != null) {
        _applyDraft(
          TxnDraft(
            type: rule.type,
            amount: rule.amount,
            date: rule.nextDue,
            accountId: rule.accountId,
            toAccountId: rule.toAccountId,
            categoryId: rule.categoryId,
            note: rule.note,
            source: TxnSource.recurring,
          ),
        );
      }
      if (widget.draft != null) _applyDraft(widget.draft!);
      _fillDefaults();
    }
  }

  Future<void> _fillDefaults() async {
    final lookups = await ref.read(lookupsProvider.future);
    if (!mounted) return;
    setState(() {
      _accountId ??= lookups.defaultAccount?.id;
      if (_type == TxnType.transfer && _toAccountId == null) {
        _toAccountId = lookups.activeAccounts.where((a) => a.id != _accountId).firstOrNull?.id;
      }
    });
  }

  void _applyDraft(TxnDraft d) {
    _type = d.type;
    if (d.amount != null) _amount.text = paiseToInput(d.amount!);
    if (d.date != null) _date = d.date!;
    _accountId = d.accountId ?? _accountId;
    _toAccountId = d.toAccountId ?? _toAccountId;
    _categoryId = d.categoryId ?? _categoryId;
    if (d.note.isNotEmpty) _note.text = d.note;
    if (d.description.isNotEmpty) _description.text = d.description;
    _payee = d.payee ?? _payee;
    _upiRef = d.upiRef ?? _upiRef;
    if (d.attachmentPath != null) _attachmentPath = d.attachmentPath;
    _source = d.source;
    _warning = d.warning;
  }

  @override
  void dispose() {
    if (!_saved && _attachmentPath != null && _attachmentPath != _originalAttachment) {
      ReceiptScanner.deleteStored(_attachmentPath);
    }
    _amount.dispose();
    _note.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _scanReceipt() async {
    final draft = await scanReceiptToDraft(context, ref);
    if (draft == null || !mounted) return;
    final previous = _attachmentPath;
    setState(() => _applyDraft(draft));
    if (previous != null && previous != _originalAttachment && previous != _attachmentPath) {
      await ReceiptScanner.deleteStored(previous);
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _date = DateTime(d.year, d.month, d.day, _date.hour, _date.minute));
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_date));
    if (t != null) setState(() => _date = DateTime(_date.year, _date.month, _date.day, t.hour, t.minute));
  }

  Future<void> _pickCategory(Lookups lookups) async {
    final kind = _type == TxnType.income ? CategoryKind.income : CategoryKind.expense;
    final picked = await showCategoryPicker(context, lookups.activeCategories(kind), selectedId: _categoryId);
    if (picked != null) setState(() => _categoryId = picked.id);
  }

  Future<void> _save({bool addAnother = false}) async {
    if (!_formKey.currentState!.validate()) return;
    final amount = parseMoney(_amount.text)!;
    final txn = Txn(
      id: widget.existing?.id,
      type: _type,
      amount: amount,
      date: _date,
      accountId: _accountId!,
      categoryId: _type == TxnType.transfer ? null : _categoryId,
      toAccountId: _type == TxnType.transfer ? _toAccountId : null,
      note: _note.text.trim(),
      description: _description.text.trim(),
      source: _source,
      attachmentPath: _attachmentPath,
      upiRef: _upiRef,
      payee: _payee,
      recurringId: widget.existing?.recurringId,
    );
    setState(() => _saving = true);
    final actions = ref.read(actionsProvider);
    try {
      if (widget.fromRule != null) {
        await actions.recordRule(widget.fromRule!, edited: txn);
      } else {
        await actions.saveTxn(txn);
        if (_repeat != null) await _createRule(txn);
      }
      _saved = true;
      await widget.onSaved?.call(txn);
      if (_originalAttachment != null && _originalAttachment != _attachmentPath) {
        await ReceiptScanner.deleteStored(_originalAttachment);
      }
    } on DuplicatePaymentException catch (e) {
      if (mounted) await _showDuplicate(e.existing);
      return;
    } on ArgumentError catch (e) {
      if (mounted) showSnack(context, '${e.message}');
      return;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted) return;
    if (addAnother) {
      showSnack(context, 'Saved ${formatMoney(amount)}');
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => TransactionFormPage(
            draft: TxnDraft(type: _type, accountId: _accountId, date: _date),
          ),
        ),
      );
    } else {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _createRule(Txn txn) async {
    const engine = RecurringEngine();
    final draftRule = RecurringRule(
      type: txn.type,
      amount: txn.amount,
      accountId: txn.accountId,
      categoryId: txn.categoryId,
      toAccountId: txn.toAccountId,
      note: txn.note,
      frequency: _repeat!,
      startDate: txn.date,
      nextDue: txn.date,
    );
    await ref.read(actionsProvider).saveRule(draftRule.copyWith(nextDue: engine.advance(draftRule, txn.date)));
    await ref.read(reminderServiceProvider).requestPermission();
  }

  Future<void> _showDuplicate(Txn existing) async {
    final open = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Already recorded'),
        content: Text(
          'A payment with UPI ref ${existing.upiRef} was saved on '
          '${fullDateFormat.format(existing.date)} for ${formatMoney(existing.amount)}.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Close')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Open it')),
        ],
      ),
    );
    if (open == true && mounted) {
      Navigator.of(context)
          .pushReplacement(MaterialPageRoute<void>(builder: (_) => TransactionFormPage(existing: existing)));
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: const Text('This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(actionsProvider).deleteTxn(widget.existing!.id!);
    await ReceiptScanner.deleteStored(_originalAttachment);
    _originalAttachment = null;
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final lookups = ref.watch(lookupsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fromRule != null ? 'Record recurring' : (_isNew ? 'New entry' : 'Edit entry')),
        actions: [
          if (_isNew && widget.fromRule == null)
            IconButton(
              tooltip: 'Fill from payment screenshot',
              icon: const AppIcon(AppIcons.scan),
              onPressed: _scanReceipt,
            ),
          if (!_isNew) IconButton(tooltip: 'Delete', icon: const AppIcon(AppIcons.delete), onPressed: _delete),
        ],
      ),
      body: AsyncBody(value: lookups, builder: _form),
    );
  }

  Widget _form(Lookups lookups) {
    final accounts = lookups.activeAccounts;
    List<Account> accountChoices(int? current) {
      final a = lookups.accountById[current];
      return [...accounts, if (a != null && a.archived) a];
    }

    final category = lookups.categoryById[_categoryId];
    final typeColor = MoneyColors.forType(context, _type);

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (_warning != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(leading: const AppIcon(AppIcons.warning), title: Text(_warning!)),
            ),
          SegmentedButton<TxnType>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: TxnType.income, label: Text('Income')),
              ButtonSegment(value: TxnType.expense, label: Text('Expense')),
              ButtonSegment(value: TxnType.transfer, label: Text('Transfer')),
            ],
            selected: {_type},
            onSelectionChanged: (s) {
              setState(() {
                final newType = s.first;
                final kindChanged = (newType == TxnType.income) != (_type == TxnType.income);
                _type = newType;
                if (kindChanged || newType == TxnType.transfer) _categoryId = null;
                if (newType == TxnType.transfer && _toAccountId == null) {
                  _toAccountId = accounts.where((a) => a.id != _accountId).firstOrNull?.id;
                }
              });
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _amount,
            autofocus: _isNew && _amount.text.isEmpty,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: typeColor, fontWeight: FontWeight.w600),
            decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ ', hintText: '0'),
            validator: (v) => parseMoney(v ?? '') == null ? 'Enter an amount' : null,
          ),
          const SizedBox(height: 12),
          if (_type != TxnType.transfer)
            FormField<int>(
              initialValue: _categoryId,
              validator: (_) => _categoryId == null ? 'Pick a category' : null,
              builder: (field) => InkWell(
                onTap: () async {
                  await _pickCategory(lookups);
                  field.didChange(_categoryId);
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Category',
                    errorText: field.errorText,
                    suffixIcon: const AppIcon(AppIcons.dropDown, size: 20),
                  ),
                  child: Text(category?.label ?? 'Choose'),
                ),
              ),
            ),
          if (_type != TxnType.transfer) const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            icon: const AppIcon(AppIcons.dropDown, size: 20),
            isExpanded: true,
            style: Theme.of(context).textTheme.bodyLarge,
            key: ValueKey('from-$_type-$_accountId'),
            initialValue: _accountId,
            decoration: InputDecoration(labelText: _type == TxnType.transfer ? 'From account' : 'Account'),
            items: [for (final a in accountChoices(_accountId)) DropdownMenuItem(value: a.id, child: Text(a.name))],
            onChanged: (v) => setState(() => _accountId = v),
            validator: (v) => v == null ? 'Pick an account' : null,
          ),
          if (_type == TxnType.transfer) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              icon: const AppIcon(AppIcons.dropDown, size: 20),
              isExpanded: true,
              style: Theme.of(context).textTheme.bodyLarge,
              key: ValueKey('to-$_toAccountId'),
              initialValue: _toAccountId,
              decoration: const InputDecoration(labelText: 'To account'),
              items: [for (final a in accountChoices(_toAccountId)) DropdownMenuItem(value: a.id, child: Text(a.name))],
              onChanged: (v) => setState(() => _toAccountId = v),
              validator: (v) {
                if (v == null) return 'Pick an account';
                if (v == _accountId) return 'Pick a different account';
                return null;
              },
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Card bill: transfer from your bank to the card. Lending: transfer to "Lent to others". '
                'Neither counts as spending.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const AppIcon(AppIcons.calendarDay, size: 18),
                  label: Text(fullDateFormat.format(_date)),
                  onPressed: _pickDate,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const AppIcon(AppIcons.time, size: 18),
                  label: Text(timeFormat.format(_date)),
                  onPressed: _pickTime,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _note,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Note', hintText: 'Lunch, Bus, Room rent…'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _description,
            minLines: 1,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Description (optional)'),
          ),
          if (_payee != null || _upiRef != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (_payee != null) Chip(avatar: const AppIcon(AppIcons.person, size: 18), label: Text(_payee!)),
                if (_upiRef != null) Chip(avatar: const AppIcon(AppIcons.tag, size: 18), label: Text('UPI $_upiRef')),
              ],
            ),
          ],
          if (_attachmentPath != null) ...[
            const SizedBox(height: 12),
            _AttachmentPreview(
              path: _attachmentPath!,
              onRemove: () => setState(() {
                if (_attachmentPath != _originalAttachment) ReceiptScanner.deleteStored(_attachmentPath);
                _attachmentPath = null;
                if (_source == TxnSource.screenshot) _source = TxnSource.manual;
              }),
            ),
          ],
          if (_isNew && widget.fromRule == null) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<Frequency?>(
              icon: const AppIcon(AppIcons.dropDown, size: 20),
              isExpanded: true,
              style: Theme.of(context).textTheme.bodyLarge,
              initialValue: _repeat,
              decoration: const InputDecoration(labelText: 'Repeat', prefixIcon: AppIcon(AppIcons.repeat)),
              items: [
                const DropdownMenuItem(value: null, child: Text('Does not repeat')),
                for (final f in Frequency.values) DropdownMenuItem(value: f, child: Text(f.label)),
              ],
              onChanged: (v) => setState(() => _repeat = v),
            ),
            if (_repeat != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'You\'ll get a reminder a day before each next one, and it waits for you to confirm. '
                  'Change this under More › Recurring payments.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
          const SizedBox(height: 28),
          Row(
            children: [
              if (_isNew && widget.fromRule == null) ...[
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    onPressed: _saving ? null : () => _save(addAnother: true),
                    child: const Text('Save & new', maxLines: 1),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: _saving ? null : _save,
                  child: Text(widget.fromRule != null ? 'Record' : 'Save', maxLines: 1),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({required this.path, required this.onRemove});
  final String path;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.file(
            file,
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const AppIcon(AppIcons.brokenImage),
          ),
        ),
        title: const Text('Payment screenshot'),
        subtitle: const Text('Tap to view'),
        trailing: IconButton(tooltip: 'Remove screenshot', icon: const AppIcon(AppIcons.close), onPressed: onRemove),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('Screenshot')),
              body: InteractiveViewer(child: Center(child: Image.file(file))),
            ),
          ),
        ),
      ),
    );
  }
}
