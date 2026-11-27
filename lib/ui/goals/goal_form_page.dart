import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/models/goal.dart';
import '../../state/providers.dart';
import '../icons.dart';

/// Adds or edits a savings goal: name, emoji, amount and an optional date.
class GoalFormPage extends ConsumerStatefulWidget {
  const GoalFormPage({super.key, this.existing});

  final Goal? existing;

  @override
  ConsumerState<GoalFormPage> createState() => _GoalFormPageState();
}

class _GoalFormPageState extends ConsumerState<GoalFormPage> {
  static const _emojis = ['🎯', '✈️', '🏠', '🚗', '📱', '💻', '🎓', '💍', '🏥', '🛟', '🎁', '🏍️'];

  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _target = TextEditingController(
    text: widget.existing == null ? '' : paiseToInput(widget.existing!.target),
  );
  late String _emoji = widget.existing?.emoji ?? _emojis.first;
  late DateTime? _by = widget.existing?.targetDate;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = DateTime.now();
    final first = DateTime(today.year, today.month, today.day);
    final d = await showDatePicker(
      context: context,
      initialDate: _by == null || _by!.isBefore(first) ? DateTime(today.year + 1, today.month, today.day) : _by!,
      firstDate: first,
      lastDate: DateTime(today.year + 50),
    );
    if (d != null) setState(() => _by = d);
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final existing = widget.existing;
    final goal = existing == null
        ? Goal(
            name: _name.text.trim(),
            emoji: _emoji,
            target: parseMoney(_target.text)!,
            targetDate: _by,
            createdAt: DateTime.now(),
          )
        : existing.copyWith(
            name: _name.text.trim(),
            emoji: _emoji,
            target: parseMoney(_target.text),
            targetDate: _by,
            clearDate: _by == null,
          );
    await ref.read(actionsProvider).saveGoal(goal);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'New goal' : 'Edit goal')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in _emojis)
                  ChoiceChip(
                    label: Text(e, style: const TextStyle(fontSize: 20)),
                    selected: e == _emoji,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _emoji = e),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Name', hintText: 'Goa trip, new phone, emergency fund…'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _target,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount to save', prefixText: '₹ '),
              validator: (v) {
                final p = parseMoney(v ?? '');
                return p == null || p <= 0 ? 'Enter an amount' : null;
              },
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const AppIcon(AppIcons.calendar),
              title: Text(_by == null ? 'No date' : 'By ${fullDateFormat.format(_by!)}'),
              subtitle: const Text('With a date, the goal shows what to put in each month'),
              onTap: _pickDate,
              trailing: _by == null
                  ? null
                  : IconButton(
                      tooltip: 'Remove the date',
                      icon: AppIcon(AppIcons.close, color: scheme.onSurfaceVariant),
                      onPressed: () => setState(() => _by = null),
                    ),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _saving ? null : _save, child: const Text('Save')),
          ],
        ),
      ),
    );
  }
}
