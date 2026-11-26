import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/money.dart';
import '../../data/finance_repository.dart';
import '../../data/models/category.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';

/// Monthly limits: one overall, and any per expense category. Leave a field
/// empty for no budget.
class BudgetSettingsPage extends ConsumerStatefulWidget {
  const BudgetSettingsPage({super.key});

  @override
  ConsumerState<BudgetSettingsPage> createState() => _BudgetSettingsPageState();
}

class _BudgetSettingsPageState extends ConsumerState<BudgetSettingsPage> {
  final Map<int, TextEditingController> _fields = {};

  TextEditingController _field(int key, Map<int, int> budgets) => _fields.putIfAbsent(
    key,
    () => TextEditingController(text: budgets[key] == null ? '' : paiseToInput(budgets[key]!)),
  );

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    await ref.read(actionsProvider).setBudgets({for (final e in _fields.entries) e.key: parseMoney(e.value.text)});
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final budgets = ref.watch(budgetsProvider);
    final lookups = ref.watch(lookupsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Monthly budgets'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: AsyncBody(
        value: budgets,
        builder: (b) => AsyncBody(
          value: lookups,
          builder: (l) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _row(context, '🧾 Total budget', _field(FinanceRepository.overallBudgetKey, b)),
              const Divider(height: 32),
              for (final c in l.activeCategories(CategoryKind.expense)) _row(context, c.label, _field(c.id!, b)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, TextEditingController controller) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        SizedBox(
          width: 140,
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(prefixText: '₹ ', hintText: 'No limit', isDense: true),
          ),
        ),
      ],
    ),
  );
}
