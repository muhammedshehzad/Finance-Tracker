import 'package:material_ui/material_ui.dart';

import '../../data/models/category.dart';
import '../categories/categories_page.dart';
import '../widgets/common.dart';

/// Grid of categories in a bottom sheet. Returns the one tapped.
Future<Category?> showCategoryPicker(BuildContext context, List<Category> categories, {int? selectedId}) {
  return showModalBottomSheet<Category>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text('Category', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CategoriesPage()));
                  },
                  child: const Text('Edit categories'),
                ),
              ],
            ),
            Flexible(
              child: GridView.count(
                shrinkWrap: true,
                crossAxisCount: 4,
                childAspectRatio: 0.85,
                children: [
                  for (final c in categories)
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.pop(context, c),
                      child: Container(
                        decoration: c.id == selectedId
                            ? BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
                              )
                            : null,
                        padding: const EdgeInsets.all(4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            EmojiAvatar(emoji: c.icon, color: Color(c.color), size: 44),
                            const SizedBox(height: 6),
                            Text(
                              c.name,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
