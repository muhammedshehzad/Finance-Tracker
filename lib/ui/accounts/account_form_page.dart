import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/money.dart';
import '../../data/models/account.dart';
import '../../state/providers.dart';

/// Adds or edits an account, including its opening balance.
class AccountFormPage extends ConsumerStatefulWidget {
  const AccountFormPage({super.key, this.existing});
  final Account? existing;

  @override
  ConsumerState<AccountFormPage> createState() => _AccountFormPageState();
}

class _AccountFormPageState extends ConsumerState<AccountFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late AccountKind _kind = widget.existing?.kind ?? AccountKind.bank;
  late final _opening = TextEditingController(text: _initialOpening());
  late final _limit = TextEditingController(
    text: widget.existing?.creditLimit == null ? '' : paiseToInput(widget.existing!.creditLimit!),
  );
  late bool _archived = widget.existing?.archived ?? false;

  /// A card's opening balance is shown as the amount owed, a positive number.
  String _initialOpening() {
    final o = widget.existing?.openingBalance ?? 0;
    if (o == 0) return '';
    final shown = widget.existing?.kind == AccountKind.creditCard ? -o : o;
    return shown < 0 ? '-${paiseToInput(-shown)}' : paiseToInput(shown);
  }

  @override
  void dispose() {
    _name.dispose();
    _opening.dispose();
    _limit.dispose();
    super.dispose();
  }

  int _parseSigned(String text) {
    final t = text.trim();
    if (t.isEmpty) return 0;
    final negative = t.startsWith('-');
    final v = parseMoney(negative ? t.substring(1) : t) ?? 0;
    return negative ? -v : v;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    var opening = _parseSigned(_opening.text);
    if (_kind == AccountKind.creditCard) opening = -opening;
    final account = Account(
      id: widget.existing?.id,
      name: _name.text.trim(),
      kind: _kind,
      openingBalance: opening,
      creditLimit: _kind == AccountKind.creditCard ? parseMoney(_limit.text) : null,
      archived: _archived,
      sortOrder: widget.existing?.sortOrder ?? 99,
    );
    await ref.read(actionsProvider).saveAccount(account);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isCard = _kind == AccountKind.creditCard;
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'New account' : 'Edit account')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name', hintText: 'SBI, HDFC card, Cash…'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<AccountKind>(
              isExpanded: true,
              style: Theme.of(context).textTheme.bodyLarge,
              initialValue: _kind,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [for (final k in AccountKind.values) DropdownMenuItem(value: k, child: Text(k.label))],
              onChanged: (v) => setState(() => _kind = v!),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _opening,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: InputDecoration(
                labelText: isCard ? 'Amount owed when you started' : 'Opening balance',
                prefixText: '₹ ',
                helperText: isCard
                    ? 'What the card statement showed as due on your start day.'
                    : 'What the account held on the day you started tracking.',
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final t = v.trim().startsWith('-') ? v.trim().substring(1) : v.trim();
                return parseMoney(t) == null ? 'Enter a valid amount' : null;
              },
            ),
            if (isCard) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _limit,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Credit limit (optional)', prefixText: '₹ '),
              ),
            ],
            if (widget.existing != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Hide this account'),
                subtitle: const Text('Old entries keep it; it stops showing in lists and pickers.'),
                value: _archived,
                onChanged: (v) => setState(() => _archived = v),
              ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _save, child: const Text('Save')),
          ],
        ),
      ),
    );
  }
}
