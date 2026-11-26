import '../../data/models/account.dart';
import '../../data/models/category.dart';
import '../../data/models/txn.dart';
import 'table_parser.dart';

/// Where rows naming a source account go.
class AccountChoice {
  const AccountChoice.existing(int this.accountId) : newKind = null;
  const AccountChoice.create(AccountKind this.newKind) : accountId = null;

  final int? accountId;
  final AccountKind? newKind;
  bool get isNew => accountId == null;
}

/// What happens to rows with a given source category.
enum CategoryAction { existing, create, transfer, skip }

/// Where rows with a source category go.
class CategoryChoice {
  const CategoryChoice.existing(int this.categoryId) : action = CategoryAction.existing, transferAccountId = null;
  const CategoryChoice.create() : action = CategoryAction.create, categoryId = null, transferAccountId = null;

  /// Record these rows as transfers to or from the app account
  /// [transferAccountId], e.g. "Credit card" or "Lent to others".
  const CategoryChoice.transfer(int this.transferAccountId) : action = CategoryAction.transfer, categoryId = null;
  const CategoryChoice.skip() : action = CategoryAction.skip, categoryId = null, transferAccountId = null;

  final CategoryAction action;
  final int? categoryId;
  final int? transferAccountId;
}

/// A source category: its name and whether it came from income or expense rows.
class SourceCategory {
  const SourceCategory(this.name, this.kind);
  final String name;
  final CategoryKind kind;

  /// Names that are usually money moving between your own accounts rather
  /// than spending, shown as a hint in the mapping screen.
  bool get looksLikeTransfer {
    final n = name.toLowerCase();
    return RegExp(
      r'credit ?card|card bill|cc bill|lend|lent|loan given|borrow|self transfer|own account|savings deposit',
    ).hasMatch(n);
  }

  @override
  bool operator ==(Object other) => other is SourceCategory && other.name == name && other.kind == kind;
  @override
  int get hashCode => Object.hash(name, kind);
}

/// The user's choices on the review screen.
class ImportMapping {
  ImportMapping({required this.accounts, required this.categories});

  /// Source account name to its target. A blank name means "no account in
  /// the file".
  final Map<String, AccountChoice> accounts;
  final Map<SourceCategory, CategoryChoice> categories;
}

/// One row ready to save. Account and category refer to source names until
/// [ImportPlan.resolve] maps them to ids.
class PlannedEntry {
  const PlannedEntry({required this.row, required this.type, required this.fromAccount, this.toAccount, this.category});

  final ParsedRow row;
  final TxnType type;
  final String fromAccount;
  final String? toAccount;
  final SourceCategory? category;
}

/// Parsed rows grouped into entries, before any account or category exists.
class ImportPlan {
  ImportPlan({required this.entries, required this.errors, required this.mergedTransferIns});

  final List<PlannedEntry> entries;

  /// Rows that can't be imported, with the reason.
  final List<ParsedRow> errors;

  /// "Transfer-In" rows dropped because they are the other half of a
  /// "Transfer-Out" row already in [entries].
  final int mergedTransferIns;

  Set<String> get accountNames => {
    for (final e in entries) ...[e.fromAccount, if (e.toAccount != null) e.toAccount!],
  };

  Set<SourceCategory> get categories => {
    for (final e in entries)
      if (e.category != null) e.category!,
  };

  DateTime? get firstDate =>
      entries.isEmpty ? null : entries.map((e) => e.row.date!).reduce((a, b) => a.isBefore(b) ? a : b);
  DateTime? get lastDate =>
      entries.isEmpty ? null : entries.map((e) => e.row.date!).reduce((a, b) => a.isAfter(b) ? a : b);

  int total(TxnType type) => entries.where((e) => e.type == type).fold(0, (s, e) => s + e.row.amount!);
}

/// Result of turning a plan into transactions.
class ResolvedImport {
  ResolvedImport({required this.txns, required this.duplicates, required this.skipped});

  final List<Txn> txns;

  /// Rows that match an entry already saved (same type, amount, minute and
  /// account), so importing the same file twice adds nothing.
  final int duplicates;

  /// Rows the user chose to skip by category.
  final int skipped;
}

/// Pure logic between parsed rows and transactions, unit tested.
class ImportPlanner {
  const ImportPlanner();

  /// Groups rows into entries, keeping only [year] when given.
  ///
  /// Some apps write each transfer twice, as an Out from one account and an
  /// In to the other. The Out is kept and its matching In is dropped.
  ImportPlan plan(List<ParsedRow> rows, {int? year}) {
    final errors = <ParsedRow>[];
    final good = <ParsedRow>[];
    for (final r in rows) {
      if (!r.ok) {
        errors.add(r);
      } else if (year == null || r.date!.year == year) {
        good.add(r);
      }
    }

    final entries = <PlannedEntry>[];
    final outs = <ParsedRow>[];
    final ins = <ParsedRow>[];
    for (final r in good) {
      switch (r.kind!) {
        case RowKind.income:
        case RowKind.expense:
          final kind = r.kind == RowKind.income ? CategoryKind.income : CategoryKind.expense;
          entries.add(
            PlannedEntry(
              row: r,
              type: r.txnType,
              fromAccount: r.account,
              category: SourceCategory(r.category.isEmpty ? 'Uncategorised' : r.category, kind),
            ),
          );
        case RowKind.transferOut:
          outs.add(r);
        case RowKind.transferIn:
          ins.add(r);
      }
    }

    for (final r in outs) {
      if (r.otherAccount.isEmpty || r.otherAccount == r.account) {
        errors.add(_withError(r, 'Transfer with no other account'));
        continue;
      }
      entries.add(PlannedEntry(row: r, type: TxnType.transfer, fromAccount: r.account, toAccount: r.otherAccount));
    }

    var merged = 0;
    final unmatchedOuts = List.of(outs);
    for (final r in ins) {
      final i = unmatchedOuts.indexWhere(
        (o) =>
            o.amount == r.amount &&
            o.date!.difference(r.date!).inMinutes.abs() <= 2 &&
            o.account == r.otherAccount &&
            o.otherAccount == r.account,
      );
      if (i >= 0) {
        unmatchedOuts.removeAt(i);
        merged++;
        continue;
      }
      if (r.otherAccount.isEmpty || r.otherAccount == r.account) {
        errors.add(_withError(r, 'Transfer with no other account'));
        continue;
      }
      entries.add(PlannedEntry(row: r, type: TxnType.transfer, fromAccount: r.otherAccount, toAccount: r.account));
    }

    entries.sort((a, b) => a.row.date!.compareTo(b.row.date!));
    return ImportPlan(entries: entries, errors: errors, mergedTransferIns: merged);
  }

  ParsedRow _withError(ParsedRow r, String error) => ParsedRow(
    rowNumber: r.rowNumber,
    date: r.date,
    kind: r.kind,
    amount: r.amount,
    category: r.category,
    account: r.account,
    toAccount: r.toAccount,
    note: r.note,
    error: error,
  );

  /// Suggested targets: same-named accounts and categories where they exist,
  /// new ones otherwise. Nothing is turned into a transfer unless asked.
  ImportMapping suggest(ImportPlan plan, List<Account> accounts, List<Category> categories, {int? fallbackAccountId}) {
    final byName = {for (final a in accounts) _key(a.name): a};
    final mapAccounts = <String, AccountChoice>{};
    for (final name in plan.accountNames) {
      final hit = byName[_key(name)];
      if (hit != null) {
        mapAccounts[name] = AccountChoice.existing(hit.id!);
      } else if (name.isEmpty && fallbackAccountId != null) {
        mapAccounts[name] = AccountChoice.existing(fallbackAccountId);
      } else {
        mapAccounts[name] = AccountChoice.create(guessKind(name));
      }
    }

    final mapCategories = <SourceCategory, CategoryChoice>{};
    for (final c in plan.categories) {
      final hit = categories.where((x) => x.kind == c.kind && _key(x.name) == _key(c.name)).firstOrNull;
      mapCategories[c] = hit != null ? CategoryChoice.existing(hit.id!) : const CategoryChoice.create();
    }
    return ImportMapping(accounts: mapAccounts, categories: mapCategories);
  }

  static AccountKind guessKind(String name) {
    final n = name.toLowerCase();
    if (RegExp(r'credit|card|amex|visa|master').hasMatch(n) && !n.contains('debit')) return AccountKind.creditCard;
    if (RegExp(r'^cash|wallet cash|in hand').hasMatch(n)) return AccountKind.cash;
    if (RegExp(r'paytm|phonepe|amazon pay|wallet|gpay|google pay').hasMatch(n)) return AccountKind.wallet;
    if (RegExp(r'lent|lend|receivable|owed').hasMatch(n)) return AccountKind.receivable;
    return AccountKind.bank;
  }

  /// Turns the plan into transactions using ids from [accountIds] and
  /// [categoryIds] (source name to id, filled after creating new ones).
  /// [existing] is what is already saved: each saved entry absorbs one
  /// matching row, so a re-import adds nothing.
  ResolvedImport resolve(
    ImportPlan plan,
    ImportMapping mapping, {
    required Map<String, int> accountIds,
    required Map<SourceCategory, int> categoryIds,
    required List<Txn> existing,
  }) {
    final seen = <String, int>{};
    for (final t in existing) {
      final k = _dupKey(t.type, t.amount, t.date, t.accountId);
      seen[k] = (seen[k] ?? 0) + 1;
    }

    final txns = <Txn>[];
    var duplicates = 0, skipped = 0;
    for (final e in plan.entries) {
      final type = e.type;
      final from = accountIds[e.fromAccount]!;
      final int? to = e.toAccount == null ? null : accountIds[e.toAccount!];
      int? categoryId;
      if (e.category != null) {
        final choice = mapping.categories[e.category!]!;
        switch (choice.action) {
          case CategoryAction.skip:
            skipped++;
            continue;
          case CategoryAction.transfer:
            final other = choice.transferAccountId!;
            if (other == from) {
              skipped++;
              continue;
            }
            final (source, target) = type == TxnType.expense ? (from, other) : (other, from);
            txns.addIfNew(_txn(e, TxnType.transfer, source, null, target), seen, () => duplicates++);
            continue;
          case CategoryAction.existing:
          case CategoryAction.create:
            categoryId = categoryIds[e.category!];
        }
      }
      if (type == TxnType.transfer && (to == null || to == from)) {
        skipped++;
        continue;
      }
      txns.addIfNew(_txn(e, type, from, categoryId, to), seen, () => duplicates++);
    }
    return ResolvedImport(txns: txns, duplicates: duplicates, skipped: skipped);
  }

  Txn _txn(PlannedEntry e, TxnType type, int from, int? categoryId, int? to) {
    final r = e.row;
    final description = [
      if (r.subcategory.isNotEmpty) r.subcategory,
      if (r.description.isNotEmpty) r.description,
    ].join(' · ');
    return Txn(
      type: type,
      amount: r.amount!,
      date: r.date!,
      accountId: from,
      categoryId: type == TxnType.transfer ? null : categoryId,
      toAccountId: type == TxnType.transfer ? to : null,
      note: r.note,
      description: description,
      source: TxnSource.imported,
    );
  }

  static String _key(String s) => s.trim().toLowerCase();
}

String _dupKey(TxnType type, int amount, DateTime date, int accountId) =>
    '${type.name}|$amount|${date.year}-${date.month}-${date.day} ${date.hour}:${date.minute}|$accountId';

extension on List<Txn> {
  void addIfNew(Txn t, Map<String, int> seen, void Function() onDuplicate) {
    final k = _dupKey(t.type, t.amount, t.date, t.accountId);
    final n = seen[k] ?? 0;
    if (n > 0) {
      seen[k] = n - 1;
      onDuplicate();
    } else {
      add(t);
    }
  }
}
