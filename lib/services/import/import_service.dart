import '../../data/finance_repository.dart';
import '../../data/models/account.dart';
import '../../data/models/category.dart';
import 'import_planner.dart';

/// What an import wrote, shown on the done screen.
class ImportResult {
  const ImportResult({
    required this.imported,
    required this.duplicates,
    required this.skipped,
    required this.newAccounts,
    required this.newCategories,
  });

  final int imported;
  final int duplicates;
  final int skipped;
  final int newAccounts;
  final int newCategories;
}

/// Saves an [ImportPlan]: creates the accounts and categories it needs, then
/// inserts every entry in one database transaction.
class ImportService {
  const ImportService(this._repo, [this._planner = const ImportPlanner()]);

  final FinanceRepository _repo;
  final ImportPlanner _planner;

  static const _palette = [
    0xFFEF5350,
    0xFFFF7043,
    0xFFFFB300,
    0xFF7CB342,
    0xFF26A69A,
    0xFF29B6F6,
    0xFF5C6BC0,
    0xFFAB47BC,
    0xFFEC407A,
    0xFF8D6E63,
  ];

  Future<ImportResult> commit(ImportPlan plan, ImportMapping mapping) async {
    final accountIds = <String, int>{};
    var newAccounts = 0;
    final existingAccounts = await _repo.accounts(includeArchived: true);
    var order = existingAccounts.fold<int>(0, (m, a) => a.sortOrder > m ? a.sortOrder : m);
    for (final name in plan.accountNames) {
      final choice = mapping.accounts[name]!;
      if (!choice.isNew) {
        accountIds[name] = choice.accountId!;
        continue;
      }
      accountIds[name] = await _repo.saveAccount(
        Account(name: name.isEmpty ? 'Imported' : name, kind: choice.newKind!, sortOrder: ++order),
      );
      newAccounts++;
    }

    final categoryIds = <SourceCategory, int>{};
    var newCategories = 0;
    for (final c in plan.categories) {
      final choice = mapping.categories[c]!;
      switch (choice.action) {
        case CategoryAction.existing:
          categoryIds[c] = choice.categoryId!;
        case CategoryAction.create:
          categoryIds[c] = await _repo.saveCategory(
            Category(
              name: c.name,
              kind: c.kind,
              icon: c.kind == CategoryKind.income ? '💰' : '🏷️',
              color: _palette[newCategories % _palette.length],
            ),
          );
          newCategories++;
        case CategoryAction.transfer:
        case CategoryAction.skip:
          break;
      }
    }

    final resolved = _planner.resolve(
      plan,
      mapping,
      accountIds: accountIds,
      categoryIds: categoryIds,
      existing: await _repo.allTxns(),
    );
    await _repo.insertTxns(resolved.txns);
    return ImportResult(
      imported: resolved.txns.length,
      duplicates: resolved.duplicates,
      skipped: resolved.skipped,
      newAccounts: newAccounts,
      newCategories: newCategories,
    );
  }
}
