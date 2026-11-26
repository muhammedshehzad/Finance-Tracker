import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/money.dart';
import '../../data/models/account.dart';
import '../../data/models/category.dart';
import '../../data/models/txn.dart';
import '../../services/voice_parser.dart';
import '../../services/voice_service.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Speech to text through Android's recogniser.
final voiceServiceProvider = Provider<VoiceService>((ref) => VoiceService());

/// Listens, splits what was said into drafts and saves them on confirm.
Future<void> showVoiceEntrySheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const VoiceEntrySheet(),
  );
}

/// Say "paid 90 for lunch and 30 for tea", check what was understood, then
/// confirm. Nothing is saved before Save is tapped.
class VoiceEntrySheet extends ConsumerStatefulWidget {
  const VoiceEntrySheet({super.key});

  @override
  ConsumerState<VoiceEntrySheet> createState() => _VoiceEntrySheetState();
}

class _VoiceEntrySheetState extends ConsumerState<VoiceEntrySheet> {
  final _transcript = TextEditingController();
  List<_EditableDraft> _drafts = [];
  bool _listening = false;
  String? _error;
  bool _saving = false;
  late final VoiceService _voice;

  @override
  void initState() {
    super.initState();
    _voice = ref.read(voiceServiceProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _voice.cancel();
    _transcript.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final ok = await _voice.init(
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _listening = false;
          _error = e == 'error_no_match' ? 'Didn\'t catch that. Tap the mic and try again.' : 'Voice error: $e';
        });
      },
      onStatus: (s) {
        if (mounted && (s == 'done' || s == 'notListening')) setState(() => _listening = false);
      },
    );
    if (!mounted) return;
    if (!ok) {
      setState(() => _error = 'Speech recognition isn\'t available. Allow the microphone, or type below.');
      return;
    }
    setState(() {
      _error = null;
      _listening = true;
    });
    await _voice.listen(
      onResult: (words, isFinal) {
        if (!mounted) return;
        _transcript.text = words;
        if (isFinal) {
          setState(() => _listening = false);
          _parse();
        } else {
          setState(() {});
        }
      },
    );
  }

  Future<void> _stop() async {
    await _voice.stop();
    if (mounted) setState(() => _listening = false);
    await _parse();
  }

  Future<void> _parse() async {
    final lookups = await ref.read(lookupsProvider.future);
    final parsed = VoiceParser(lookups.categories).parse(_transcript.text);
    if (!mounted) return;
    setState(() {
      _drafts = parsed.map((d) => _EditableDraft.from(d, lookups)).toList();
    });
  }

  Future<void> _save() async {
    final valid = _drafts.where((d) => d.isValid).toList();
    if (valid.isEmpty) return;
    setState(() => _saving = true);
    final now = DateTime.now();
    try {
      await ref.read(actionsProvider).saveTxns([
        for (final d in valid)
          Txn(
            type: d.type,
            amount: d.amount!,
            date: now,
            accountId: d.accountId!,
            categoryId: d.type == TxnType.transfer ? null : d.categoryId,
            toAccountId: d.type == TxnType.transfer ? d.toAccountId : null,
            note: d.note,
            payee: d.payee,
            source: TxnSource.voice,
          ),
      ]);
    } on ArgumentError catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showSnack(context, '${e.message}');
      }
      return;
    }
    if (!mounted) return;
    final total = valid.fold<int>(0, (s, d) => s + d.amount!);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Saved ${valid.length} ${valid.length == 1 ? 'entry' : 'entries'} · ${formatMoney(total)}'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lookups = ref.watch(lookupsProvider);
    final validCount = _drafts.where((d) => d.isValid).length;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _listening ? 'Listening…' : 'Say what you paid or received',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton.filled(
                    iconSize: 28,
                    tooltip: _listening ? 'Stop' : 'Speak again',
                    icon: Icon(_listening ? Icons.stop : Icons.mic),
                    onPressed: _listening ? _stop : _start,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: _transcript,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'e.g. "lunch 90 and bus 26 by cash" or "rent 2500"',
                  helperText: _error,
                  helperStyle: TextStyle(color: Theme.of(context).colorScheme.error),
                  suffixIcon: IconButton(
                    tooltip: 'Read this text',
                    icon: const Icon(Icons.keyboard_return),
                    onPressed: _parse,
                  ),
                ),
                onSubmitted: (_) => _parse(),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: AsyncBody(
                value: lookups,
                builder: (l) {
                  if (_drafts.isEmpty) {
                    return EmptyState(
                      icon: Icons.record_voice_over_outlined,
                      message: _transcript.text.isEmpty || _listening
                          ? 'Say an amount and what it was for.'
                          : 'No amount found. Try "paid 90 for lunch".',
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _drafts.length,
                    itemBuilder: (_, i) => _DraftCard(
                      key: ObjectKey(_drafts[i]),
                      draft: _drafts[i],
                      lookups: l,
                      onChanged: () => setState(() {}),
                      onRemove: () => setState(() => _drafts.removeAt(i)),
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: validCount == 0 || _saving ? null : _save,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(validCount <= 1 ? 'Confirm and save' : 'Confirm and save $validCount entries'),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditableDraft {
  _EditableDraft({
    required this.type,
    required this.amount,
    required this.categoryId,
    required this.accountId,
    required this.toAccountId,
    required this.note,
    required this.payee,
  });

  factory _EditableDraft.from(VoiceDraft d, Lookups l) {
    int? accountFor(AccountKind? kind) => (kind == null ? null : l.firstOfKind(kind))?.id ?? l.defaultAccount?.id;
    return _EditableDraft(
      type: d.type,
      amount: d.amountPaise,
      categoryId: d.categoryId,
      accountId: accountFor(d.accountHint),
      toAccountId: d.toAccountHint == null ? null : l.firstOfKind(d.toAccountHint!)?.id,
      note: d.note,
      payee: d.payee,
    );
  }

  TxnType type;
  int? amount;
  int? categoryId;
  int? accountId;
  int? toAccountId;
  String note;
  String? payee;

  bool get isValid =>
      amount != null &&
      amount! > 0 &&
      accountId != null &&
      (type == TxnType.transfer ? toAccountId != null && toAccountId != accountId : categoryId != null);
}

class _DraftCard extends StatefulWidget {
  const _DraftCard({
    super.key,
    required this.draft,
    required this.lookups,
    required this.onChanged,
    required this.onRemove,
  });

  final _EditableDraft draft;
  final Lookups lookups;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  State<_DraftCard> createState() => _DraftCardState();
}

class _DraftCardState extends State<_DraftCard> {
  late final _amount = TextEditingController(
    text: widget.draft.amount == null ? '' : paiseToInput(widget.draft.amount!),
  );
  late final _note = TextEditingController(text: widget.draft.note);

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    final l = widget.lookups;
    final accounts = l.activeAccounts;
    final typeLabel = switch (d.type) {
      TxnType.income => 'Income',
      TxnType.expense => 'Expense',
      TxnType.transfer => 'Transfer',
    };
    final categories = l.activeCategories(d.type == TxnType.income ? CategoryKind.income : CategoryKind.expense);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
        child: Column(
          children: [
            Row(
              children: [
                Chip(
                  label: Text(typeLabel),
                  labelStyle: TextStyle(color: MoneyColors.forType(context, d.type)),
                  visualDensity: VisualDensity.compact,
                ),
                const Spacer(),
                if (!d.isValid)
                  Text('Needs a fix', style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
                IconButton(tooltip: 'Remove', icon: const Icon(Icons.close), onPressed: widget.onRemove),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 120,
                        child: TextField(
                          controller: _amount,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ ', isDense: true),
                          onChanged: (v) {
                            d.amount = parseMoney(v);
                            widget.onChanged();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _note,
                          decoration: const InputDecoration(labelText: 'Note', isDense: true),
                          onChanged: (v) => d.note = v.trim(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (d.type != TxnType.transfer)
                    DropdownButtonFormField<int>(
                      isExpanded: true,
                      style: Theme.of(context).textTheme.bodyLarge,
                      initialValue: d.categoryId,
                      isDense: true,
                      decoration: const InputDecoration(labelText: 'Category', isDense: true),
                      items: [for (final c in categories) DropdownMenuItem(value: c.id, child: Text(c.label))],
                      onChanged: (v) {
                        d.categoryId = v;
                        widget.onChanged();
                      },
                    ),
                  if (d.type != TxnType.transfer) const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          isExpanded: true,
                          style: Theme.of(context).textTheme.bodyLarge,
                          initialValue: d.accountId,
                          isDense: true,
                          decoration: InputDecoration(
                            labelText: d.type == TxnType.transfer ? 'From' : 'Account',
                            isDense: true,
                          ),
                          items: [for (final a in accounts) DropdownMenuItem(value: a.id, child: Text(a.name))],
                          onChanged: (v) {
                            d.accountId = v;
                            widget.onChanged();
                          },
                        ),
                      ),
                      if (d.type == TxnType.transfer) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            isExpanded: true,
                            style: Theme.of(context).textTheme.bodyLarge,
                            initialValue: d.toAccountId,
                            isDense: true,
                            decoration: const InputDecoration(labelText: 'To', isDense: true),
                            items: [for (final a in accounts) DropdownMenuItem(value: a.id, child: Text(a.name))],
                            onChanged: (v) {
                              d.toAccountId = v;
                              widget.onChanged();
                            },
                          ),
                        ),
                      ],
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
