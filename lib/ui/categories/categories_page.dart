import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models/category.dart';
import '../../state/providers.dart';
import '../icons.dart';
import '../widgets/common.dart';

/// Expense and income categories, to add, edit or archive.
class CategoriesPage extends ConsumerWidget {
  const CategoriesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lookups = ref.watch(lookupsProvider);
    return DefaultTabController(
      length: 2,
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('Categories'),
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Expense'),
                Tab(text: 'Income'),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton(
            tooltip: 'Add category',
            onPressed: () {
              final kind = DefaultTabController.of(context).index == 0 ? CategoryKind.expense : CategoryKind.income;
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CategoryFormPage(kind: kind)));
            },
            child: const AppIcon(AppIcons.add),
          ),
          body: AsyncBody(
            value: lookups,
            builder: (l) => TabBarView(
              children: [
                for (final kind in [CategoryKind.expense, CategoryKind.income])
                  ListView(
                    padding: const EdgeInsets.only(bottom: 96),
                    children: [
                      for (final c in l.categories.where((c) => c.kind == kind))
                        ListTile(
                          leading: EmojiAvatar(emoji: c.icon, color: Color(c.color)),
                          title: Text(c.name),
                          subtitle: Text(
                            c.archived ? 'Hidden' : (c.keywords.isEmpty ? 'No voice keywords' : c.keywords.join(', ')),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => CategoryFormPage(kind: kind, existing: c),
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Adds or edits a category.
class CategoryFormPage extends ConsumerStatefulWidget {
  const CategoryFormPage({super.key, required this.kind, this.existing});
  final CategoryKind kind;
  final Category? existing;

  @override
  ConsumerState<CategoryFormPage> createState() => _CategoryFormPageState();
}

class _CategoryFormPageState extends ConsumerState<CategoryFormPage> {
  static const _palette = [
    0xFFEF5350,
    0xFFFF7043,
    0xFFFFB300,
    0xFFFFEE58,
    0xFF7CB342,
    0xFF66BB6A,
    0xFF26A69A,
    0xFF26C6DA,
    0xFF29B6F6,
    0xFF42A5F5,
    0xFF5C6BC0,
    0xFFAB47BC,
    0xFFEC407A,
    0xFF8D6E63,
    0xFF9E9E9E,
  ];

  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _icon = TextEditingController(text: widget.existing?.icon ?? '🏷️');
  late final _keywords = TextEditingController(text: widget.existing?.keywords.join(', ') ?? '');
  late int _color = widget.existing?.color ?? _palette[8];
  late bool _archived = widget.existing?.archived ?? false;

  @override
  void dispose() {
    _name.dispose();
    _icon.dispose();
    _keywords.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final c = Category(
      id: widget.existing?.id,
      name: _name.text.trim(),
      kind: widget.kind,
      icon: _icon.text.trim().isEmpty ? '•' : _icon.text.trim(),
      color: _color,
      keywords: _keywords.text.split(',').map((s) => s.trim().toLowerCase()).where((s) => s.isNotEmpty).toList(),
      archived: _archived,
      sortOrder: widget.existing?.sortOrder ?? 0,
    );
    await ref.read(actionsProvider).saveCategory(c);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'New category' : 'Edit category')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                SizedBox(
                  width: 80,
                  child: TextFormField(
                    controller: _icon,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 24),
                    decoration: const InputDecoration(labelText: 'Emoji'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Name'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in _palette)
                  GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: Color(c),
                      child: c == _color ? const AppIcon(AppIcons.check, color: Colors.black87, size: 18) : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _keywords,
              decoration: const InputDecoration(
                labelText: 'Voice keywords',
                hintText: 'lunch, tea, breakfast',
                helperText: 'Saying any of these words picks this category.',
              ),
            ),
            if (widget.existing != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Hide this category'),
                subtitle: const Text('Old entries keep it.'),
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
