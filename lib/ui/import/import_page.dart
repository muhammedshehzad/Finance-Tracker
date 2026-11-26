import 'dart:developer';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/models/account.dart';
import '../../data/models/category.dart';
import '../../data/models/txn.dart';
import '../../services/import/import_planner.dart';
import '../../services/import/import_service.dart';
import '../../services/import/sheet_reader.dart';
import '../../services/import/table_parser.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Imports entries from an Excel (.xlsx) or CSV file: pick the file, check
/// how its columns, accounts and categories map, then import.
class ImportPage extends ConsumerStatefulWidget {
  const ImportPage({super.key, this.initialFile});

  /// For tests and previews: skip the picker and load this file.
  final ({String name, Uint8List bytes})? initialFile;

  @override
  ConsumerState<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends ConsumerState<ImportPage> {
  static const _parser = TableParser();
  static const _planner = ImportPlanner();

  String? _fileName;
  Uint8List? _bytes;
  SheetData? _sheet;
  int _headerRow = 0;
  Map<int, ImportField> _columns = {};
  ParseOptions _options = const ParseOptions();
  int? _year;
  List<int> _years = [];
  ImportPlan? _plan;
  ImportMapping? _mapping;
  bool _busy = false;
  String? _error;
  ImportResult? _result;

  @override
  void initState() {
    super.initState();
    final f = widget.initialFile;
    if (f != null) WidgetsBinding.instance.addPostFrameCallback((_) => _load(f.name, f.bytes));
  }

  Future<void> _pick() async {
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['xlsx', 'csv']);
    if (file == null) return;
    setState(() => _busy = true);
    try {
      await _load(file.name, await file.readAsBytes());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load(String name, Uint8List bytes, {String? sheetName}) async {
    try {
      final sheet = const SheetReader().read(name, bytes, sheetName: sheetName);
      final header = _parser.findHeaderRow(sheet.rows);
      final columns = sheet.rows.isEmpty ? <int, ImportField>{} : _parser.guessColumns(sheet.rows[header]);
      final dateCol = columns.entries.where((e) => e.value == ImportField.date).firstOrNull?.key;
      final dayFirst = dateCol == null ? null : _parser.detectDayFirst(sheet.rows, header, dateCol);
      setState(() {
        _error = null;
        _fileName = name;
        _bytes = bytes;
        _sheet = sheet;
        _headerRow = header;
        _columns = columns;
        _options = ParseOptions(dayFirst: dayFirst ?? true);
        _mapping = null;
        _year = null;
        _years = [];
      });
      await _replan(chooseYear: true);
    } on UnsupportedFileException catch (e) {
      setState(() => _error = e.message);
    }
  }

  /// Re-reads rows after any change, keeping mapping choices already made.
  Future<void> _replan({bool chooseYear = false}) async {
    final sheet = _sheet;
    if (sheet == null) return;
    final rows = _parser.parse(sheet.rows, _headerRow, _columns, _options);
    final years = {
      for (final r in rows)
        if (r.ok) r.date!.year,
    }.toList()..sort();
    if (chooseYear) {
      final now = DateTime.now().year;
      _year = years.contains(now) ? now : null;
    } else if (_year != null && !years.contains(_year)) {
      _year = null;
    }
    final plan = _planner.plan(rows, year: _year);
    final lookups = await ref.read(lookupsProvider.future);
    final fresh = _planner.suggest(
      plan,
      lookups.accounts,
      lookups.categories,
      fallbackAccountId: lookups.defaultAccount?.id,
    );
    final old = _mapping;
    if (old != null) {
      for (final k in fresh.accounts.keys.toList()) {
        if (old.accounts.containsKey(k)) fresh.accounts[k] = old.accounts[k]!;
      }
      for (final k in fresh.categories.keys.toList()) {
        if (old.categories.containsKey(k)) fresh.categories[k] = old.categories[k]!;
      }
    }
    if (!mounted) return;
    setState(() {
      _years = years;
      _plan = plan;
      _mapping = fresh;
    });
  }

  Future<void> _import() async {
    final plan = _plan, mapping = _mapping;
    if (plan == null || mapping == null) return;
    setState(() => _busy = true);
    try {
      final result = await ref.read(actionsProvider).importPlan(plan, mapping);
      if (mounted) setState(() => _result = result);
    } catch (e, st) {
      log('Import failed', error: e, stackTrace: st);
      if (mounted) showSnack(context, 'Nothing was imported. Your entries are unchanged.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import from Excel'),
        actions: [
          if (_sheet != null && result == null)
            TextButton(onPressed: _busy ? null : _pick, child: const Text('Change file')),
        ],
      ),
      body: result != null
          ? _ResultView(result: result)
          : _sheet == null
          ? _intro(context)
          : _mappingView(context),
      bottomNavigationBar: _bottomBar(context),
    );
  }

  Widget? _bottomBar(BuildContext context) {
    final plan = _plan;
    if (_result != null) {
      return _BottomAction(
        child: FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
      );
    }
    if (_sheet == null || plan == null) return null;
    final n = plan.entries.length;
    return _BottomAction(
      child: FilledButton(
        onPressed: n == 0 || _busy ? null : _import,
        child: _busy
            ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(n == 0 ? 'Nothing to import' : 'Import ${_count(n, 'entry', 'entries')}'),
      ),
    );
  }

  Widget _intro(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Icon(Icons.table_view_outlined, size: 48, color: Theme.of(context).colorScheme.primary),
        ),
        const SizedBox(height: 16),
        Text('Bring in your past entries', style: t.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'Pick an .xlsx or .csv file. You will see how its columns, accounts and categories match '
          'before anything is saved.',
          style: t.bodyMedium?.copyWith(color: muted),
        ),
        const SizedBox(height: 24),
        _tip(
          context,
          Icons.ios_share,
          'From Money Manager',
          'More, then Export to Excel. Share the file to your phone and pick it here.',
        ),
        _tip(
          context,
          Icons.view_column_outlined,
          'From your own sheet',
          'One row per entry with at least a date and an amount. Type, category, account and note columns are picked up by their headings.',
        ),
        _tip(
          context,
          Icons.content_copy_outlined,
          'Safe to run twice',
          'Entries already in the app are skipped, so importing the same file again adds nothing.',
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: t.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _busy ? null : _pick,
          icon: _busy
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.upload_file),
          label: const Text('Choose file'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
      ],
    );
  }

  Widget _tip(BuildContext context, IconData icon, String title, String body) =>
      ListTile(contentPadding: EdgeInsets.zero, leading: Icon(icon), title: Text(title), subtitle: Text(body));

  Widget _mappingView(BuildContext context) {
    final plan = _plan;
    final mapping = _mapping;
    final lookups = ref.watch(lookupsProvider);
    if (plan == null || mapping == null) return const Center(child: CircularProgressIndicator());
    return AsyncBody(
      value: lookups,
      builder: (l) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _SummaryCard(plan: plan, fileName: _fileName!, sheet: _sheet!),
          if (_sheet!.otherSheets.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              isExpanded: true,
              style: Theme.of(context).textTheme.bodyLarge,
              initialValue: _sheet!.name,
              decoration: const InputDecoration(labelText: 'Sheet'),
              items: [
                for (final s in [_sheet!.name, ..._sheet!.otherSheets]) DropdownMenuItem(value: s, child: Text(s)),
              ],
              onChanged: (s) => _load(_fileName!, _bytes!, sheetName: s),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int?>(
                  key: ValueKey('year-$_year-${_years.length}'),
                  isExpanded: true,
                  style: Theme.of(context).textTheme.bodyLarge,
                  initialValue: _year,
                  decoration: const InputDecoration(labelText: 'Entries from'),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('All years')),
                    for (final y in _years.reversed) DropdownMenuItem<int?>(value: y, child: Text('$y only')),
                  ],
                  onChanged: (y) {
                    _year = y;
                    _replan();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<bool>(
                  isExpanded: true,
                  style: Theme.of(context).textTheme.bodyLarge,
                  initialValue: _options.dayFirst,
                  decoration: const InputDecoration(labelText: 'Dates read as'),
                  items: const [
                    DropdownMenuItem(value: true, child: Text('Day / month')),
                    DropdownMenuItem(value: false, child: Text('Month / day')),
                  ],
                  onChanged: (v) {
                    _options = ParseOptions(dayFirst: v!, defaultKind: _options.defaultKind);
                    _replan();
                  },
                ),
              ),
            ],
          ),
          if (!_columns.containsValue(ImportField.type) &&
              !_columns.containsValue(ImportField.income) &&
              !_columns.containsValue(ImportField.expense)) ...[
            const SizedBox(height: 16),
            Text('The file has no type column. Positive amounts are:', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            SegmentedButton<RowKind>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: RowKind.expense, label: Text('Expenses')),
                ButtonSegment(value: RowKind.income, label: Text('Income')),
              ],
              selected: {_options.defaultKind},
              onSelectionChanged: (s) {
                _options = ParseOptions(dayFirst: _options.dayFirst, defaultKind: s.first);
                _replan();
              },
            ),
          ],
          _section(context, 'Columns'),
          _ColumnsCard(
            header: _sheet!.rows.isEmpty ? const [] : _sheet!.rows[_headerRow],
            sample: _sheet!.rows.length > _headerRow + 1 ? _sheet!.rows[_headerRow + 1] : const [],
            columns: _columns,
            onChanged: (i, f) {
              setState(() => _columns = {..._columns, i: f});
              _replan();
            },
          ),
          if (plan.accountNames.isNotEmpty) ...[
            _section(context, 'Accounts'),
            for (final name in plan.accountNames.toList()..sort())
              _accountRow(context, name, mapping, l.activeAccounts),
          ],
          if (plan.categories.isNotEmpty) ...[
            _section(context, 'Categories'),
            for (final c in _sortedCategories(plan))
              _categoryRow(context, c, plan, mapping, l.activeCategories(c.kind), l.activeAccounts),
          ],
          if (plan.errors.isNotEmpty) ...[
            _section(context, '${_count(plan.errors.length, 'row', 'rows')} will be left out'),
            for (final r in plan.errors.take(20))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Text('Row ${r.rowNumber}', style: Theme.of(context).textTheme.labelMedium),
                title: Text(r.error!),
              ),
            if (plan.errors.length > 20)
              Text('and ${plan.errors.length - 20} more', style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }

  List<SourceCategory> _sortedCategories(ImportPlan plan) {
    final counts = <SourceCategory, int>{};
    for (final e in plan.entries) {
      if (e.category != null) counts[e.category!] = (counts[e.category!] ?? 0) + 1;
    }
    return counts.keys.toList()
      ..sort((a, b) => a.kind != b.kind ? a.kind.index.compareTo(b.kind.index) : counts[b]!.compareTo(counts[a]!));
  }

  Widget _section(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 8),
    child: Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );

  Widget _accountRow(BuildContext context, String name, ImportMapping mapping, List<Account> accounts) {
    final choice = mapping.accounts[name]!;
    final value = choice.isNew ? 'new:${choice.newKind!.name}' : 'id:${choice.accountId}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        key: ValueKey('acc-$name-$value'),
        isExpanded: true,
        style: Theme.of(context).textTheme.bodyLarge,
        initialValue: value,
        decoration: InputDecoration(labelText: name.isEmpty ? 'Rows with no account' : '"$name" in the file'),
        items: [
          for (final a in accounts) DropdownMenuItem(value: 'id:${a.id}', child: Text(a.name)),
          for (final k in AccountKind.values)
            DropdownMenuItem(
              value: 'new:${k.name}',
              child: Text('New ${k.label.toLowerCase()} "${name.isEmpty ? 'Imported' : name}"'),
            ),
        ],
        onChanged: (v) => setState(() {
          mapping.accounts[name] = v!.startsWith('id:')
              ? AccountChoice.existing(int.parse(v.substring(3)))
              : AccountChoice.create(AccountKind.fromName(v.substring(4)));
        }),
      ),
    );
  }

  Widget _categoryRow(
    BuildContext context,
    SourceCategory c,
    ImportPlan plan,
    ImportMapping mapping,
    List<Category> categories,
    List<Account> accounts,
  ) {
    final choice = mapping.categories[c]!;
    final value = switch (choice.action) {
      CategoryAction.existing => 'id:${choice.categoryId}',
      CategoryAction.create => 'new',
      CategoryAction.transfer => 'tr:${choice.transferAccountId}',
      CategoryAction.skip => 'skip',
    };
    final rows = plan.entries.where((e) => e.category == c);
    final total = rows.fold<int>(0, (s, e) => s + e.row.amount!);
    final kindWord = c.kind == CategoryKind.income ? 'income' : 'expense';
    final transferWord = c.kind == CategoryKind.income ? 'Transfer back from' : 'Transfer to';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        key: ValueKey('cat-${c.name}-${c.kind.name}-$value'),
        isExpanded: true,
        style: Theme.of(context).textTheme.bodyLarge,
        initialValue: value,
        decoration: InputDecoration(
          labelText: '${c.name} · ${_count(rows.length, kindWord, '${kindWord}s')} · ${formatMoney(total)}',
          helperText: c.looksLikeTransfer && choice.action != CategoryAction.transfer
              ? 'Often a transfer between your own accounts. Keep it as a category if this is your only record of that spending.'
              : null,
          helperMaxLines: 3,
        ),
        items: [
          for (final x in categories) DropdownMenuItem(value: 'id:${x.id}', child: Text(x.label)),
          DropdownMenuItem(value: 'new', child: Text('New category "${c.name}"')),
          for (final a in accounts) DropdownMenuItem(value: 'tr:${a.id}', child: Text('$transferWord ${a.name}')),
          const DropdownMenuItem(value: 'skip', child: Text("Don't import")),
        ],
        onChanged: (v) => setState(() {
          mapping.categories[c] = switch (v!) {
            'new' => const CategoryChoice.create(),
            'skip' => const CategoryChoice.skip(),
            _ when v.startsWith('tr:') => CategoryChoice.transfer(int.parse(v.substring(3))),
            _ => CategoryChoice.existing(int.parse(v.substring(3))),
          };
        }),
      ),
    );
  }
}

String _count(int n, String one, String many) => '${formatCount(n)} ${n == 1 ? one : many}';

/// A count with Indian digit grouping, such as 1,20,000.
String formatCount(int n) => formatMoney(n * 100, symbol: false).replaceAll(RegExp(r'\.00$'), '');

class _BottomAction extends StatelessWidget {
  const _BottomAction({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: SizedBox(height: 52, width: double.infinity, child: child),
    ),
  );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.plan, required this.fileName, required this.sheet});
  final ImportPlan plan;
  final String fileName;
  final SheetData sheet;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final first = plan.firstDate, last = plan.lastDate;
    final transfers = plan.entries.where((e) => e.type == TxnType.transfer).length;
    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              fileName,
              style: t.labelMedium?.copyWith(color: muted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              _count(plan.entries.length, 'entry', 'entries'),
              style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (first != null && last != null)
              Text(
                '${fullDateFormat.format(first)} to ${fullDateFormat.format(last)}',
                style: t.bodyMedium?.copyWith(color: muted),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                _cell(context, 'Income', formatMoney(plan.total(TxnType.income)), MoneyColors.income(context)),
                _cell(context, 'Expenses', formatMoney(plan.total(TxnType.expense)), MoneyColors.expense(context)),
                _cell(context, 'Transfers', '$transfers', null),
              ],
            ),
            if (plan.mergedTransferIns > 0) ...[
              const SizedBox(height: 8),
              Text(
                '${_count(plan.mergedTransferIns, 'transfer was', 'transfers were')} listed twice (out and in); each is imported once.',
                style: t.bodySmall?.copyWith(color: muted),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _cell(BuildContext context, String label, String value, Color? color) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        Text(
          value,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(color: color),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    ),
  );
}

class _ColumnsCard extends StatelessWidget {
  const _ColumnsCard({required this.header, required this.sample, required this.columns, required this.onChanged});
  final List<Object?> header;
  final List<Object?> sample;
  final Map<int, ImportField> columns;
  final void Function(int column, ImportField field) onChanged;

  String _text(Object? v) {
    if (v == null) return '';
    if (v is DateTime) return fullDateFormat.format(v);
    if (v is double && v == v.roundToDouble()) return v.toInt().toString();
    return v.toString();
  }

  @override
  Widget build(BuildContext context) {
    final matched = [
      for (final f in ImportField.values)
        if (f != ImportField.ignore && columns.containsValue(f)) f.label.split(' (').first,
    ];
    final missing =
        !columns.containsValue(ImportField.date) ||
        !(columns.containsValue(ImportField.amount) ||
            columns.containsValue(ImportField.income) ||
            columns.containsValue(ImportField.expense));
    return Card.outlined(
      shape: outlinedCardShape(context),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: missing,
        shape: const Border(),
        title: Text(missing ? 'Pick the date and amount columns' : '${matched.length} columns matched'),
        subtitle: Text(
          matched.isEmpty ? 'None recognised' : matched.join(', '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          for (var i = 0; i < header.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: DropdownButtonFormField<ImportField>(
                key: ValueKey('col-$i-${columns[i]}'),
                isExpanded: true,
                style: Theme.of(context).textTheme.bodyLarge,
                initialValue: columns[i] ?? ImportField.ignore,
                decoration: InputDecoration(
                  labelText: _text(header[i]).isEmpty ? 'Column ${i + 1}' : _text(header[i]),
                  helperText: _text(i < sample.length ? sample[i] : null).isEmpty ? null : 'e.g. ${_text(sample[i])}',
                ),
                items: [for (final f in ImportField.values) DropdownMenuItem(value: f, child: Text(f.label))],
                onChanged: (f) => onChanged(i, f!),
              ),
            ),
        ],
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({required this.result});
  final ImportResult result;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final lines = [
      if (result.duplicates > 0)
        '${_count(result.duplicates, 'entry was', 'entries were')} already in the app, so skipped.',
      if (result.skipped > 0) '${_count(result.skipped, 'row', 'rows')} left out as you chose.',
      if (result.newAccounts > 0) '${_count(result.newAccounts, 'account', 'accounts')} added.',
      if (result.newCategories > 0) '${_count(result.newCategories, 'category', 'categories')} added.',
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Icon(Icons.check_circle_outline, size: 56, color: Theme.of(context).colorScheme.primary),
        ),
        const SizedBox(height: 16),
        Text('Imported ${_count(result.imported, 'entry', 'entries')}', style: t.headlineSmall),
        const SizedBox(height: 12),
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(l, style: t.bodyMedium?.copyWith(color: muted)),
          ),
        const SizedBox(height: 24),
        Card.outlined(
          shape: outlinedCardShape(context),
          child: ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: const Text('Check your opening balances'),
            subtitle: const Text(
              'Balances count from what each account held before the first imported entry. '
              'Set that in Accounts so they match your bank.',
            ),
          ),
        ),
      ],
    );
  }
}
