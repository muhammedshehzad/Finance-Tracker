import '../data/models/category.dart';

/// Picks the category whose name or keywords best match free text such as a
/// spoken phrase ("tea and snacks") or a payee name from a receipt.
class CategoryMatcher {
  CategoryMatcher(this.categories);

  final List<Category> categories;

  /// The best-scoring active category of [kind], or null when nothing
  /// matches. "Akhira (charity)" also matches the bare word "akhira".
  Category? match(String text, CategoryKind kind) {
    final lower = ' ${text.toLowerCase()} ';
    Category? best;
    var bestScore = 0;
    for (final c in categories.where((c) => c.kind == kind && !c.archived)) {
      var score = 0;
      if (_containsWord(lower, c.name.toLowerCase())) score += 3;
      final bareName = c.name.toLowerCase().replaceAll(RegExp(r'\s*\(.*\)'), '');
      if (bareName != c.name.toLowerCase() && _containsWord(lower, bareName)) score += 3;
      for (final k in c.keywords) {
        if (_containsWord(lower, k.toLowerCase())) score += 2 + (k.contains(' ') ? 1 : 0);
      }
      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }
    return best;
  }

  /// The catch-all category for [kind]: "Other" / "Other income", or the last one.
  Category? fallback(CategoryKind kind) {
    final list = categories.where((c) => c.kind == kind && !c.archived).toList();
    if (list.isEmpty) return null;
    return list.firstWhere((c) => c.name.toLowerCase().startsWith('other'), orElse: () => list.last);
  }

  static bool _containsWord(String haystack, String word) {
    if (word.isEmpty) return false;
    return RegExp('(^|[^a-z])${RegExp.escape(word)}(\$|[^a-z])').hasMatch(haystack);
  }
}
