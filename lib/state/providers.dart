import 'dart:developer';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/dates.dart';
import '../data/finance_repository.dart';
import '../data/models/account.dart';
import '../data/models/captured_payment.dart';
import '../data/models/category.dart';
import '../data/models/goal.dart';
import '../data/models/recurring_rule.dart';
import '../data/models/txn.dart';
import '../data/models/txn_draft.dart';
import '../services/ai/gemini_service.dart';
import '../services/backup/auto_backup_service.dart';
import '../services/backup/backup_folder_channel.dart';
import '../services/backup_service.dart';
import '../services/capture/capture_channel.dart';
import '../services/capture/capture_service.dart';
import '../services/capture/notification_parser.dart';
import '../services/category_matcher.dart';
import '../services/import/import_planner.dart';
import '../services/import/import_service.dart';
import '../services/insights_service.dart';
import '../services/lock/app_lock_service.dart';
import '../services/recurring_service.dart';
import '../services/reminder_service.dart';

/// The opened database. Overridden in `main()` and in tests.
final repositoryProvider = Provider<FinanceRepository>(
  (ref) => throw UnimplementedError('repositoryProvider must be overridden'),
);

/// Reads screenshots and voice notes with Gemini when the build has it set up.
final geminiServiceProvider = Provider<GeminiService>((ref) => GeminiService());

/// Backs up all data to a JSON file and restores it.
final backupServiceProvider = Provider<BackupService>((ref) => BackupService(ref.watch(repositoryProvider).database));

/// Schedules local reminders for recurring payments.
final reminderServiceProvider = Provider<ReminderService>((ref) => ReminderService());

/// Records, skips and auto-posts recurring payments.
final recurringServiceProvider = Provider<RecurringService>((ref) => RecurringService(ref.watch(repositoryProvider)));

/// A counter bumped after every write. Each read provider below watches it,
/// so one write refreshes every screen; the queries are small local SQLite
/// reads, so refreshing them together is cheap and never stale.
class DbRevision extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

/// See [DbRevision].
final dbRevisionProvider = NotifierProvider<DbRevision, int>(DbRevision.new);

/// The month the Transactions and Stats screens are showing.
class SelectedMonth extends Notifier<DateTime> {
  @override
  DateTime build() => startOfMonth(DateTime.now());
  void set(DateTime month) => state = startOfMonth(month);
  void previous() => state = DateTime(state.year, state.month - 1);
  void next() => state = DateTime(state.year, state.month + 1);
}

/// See [SelectedMonth].
final selectedMonthProvider = NotifierProvider<SelectedMonth, DateTime>(SelectedMonth.new);

/// Accounts and categories by id, for showing names on entries.
class Lookups {
  Lookups(this.accounts, this.categories)
    : accountById = {for (final a in accounts) a.id!: a},
      categoryById = {for (final c in categories) c.id!: c};

  /// All accounts and categories, archived ones included, so old entries
  /// still show their names.
  final List<Account> accounts;
  final List<Category> categories;
  final Map<int, Account> accountById;
  final Map<int, Category> categoryById;

  /// Accounts that are not archived, for pickers.
  List<Account> get activeAccounts => accounts.where((a) => !a.archived).toList();

  /// Categories of [kind] that are not archived, for pickers.
  List<Category> activeCategories(CategoryKind kind) => categories.where((c) => c.kind == kind && !c.archived).toList();

  /// The first active account of [kind], if any.
  Account? firstOfKind(AccountKind kind) {
    for (final a in activeAccounts) {
      if (a.kind == kind) return a;
    }
    return null;
  }

  /// Account used when nothing else says which: the first bank account.
  Account? get defaultAccount =>
      firstOfKind(AccountKind.bank) ?? (activeAccounts.isEmpty ? null : activeAccounts.first);
}

/// See [Lookups].
final lookupsProvider = FutureProvider<Lookups>((ref) async {
  ref.watch(dbRevisionProvider);
  final repo = ref.watch(repositoryProvider);
  return Lookups(await repo.accounts(includeArchived: true), await repo.categories(includeArchived: true));
});

/// Current balance of every account, by account id, in paise.
final balancesProvider = FutureProvider<Map<int, int>>((ref) async {
  ref.watch(dbRevisionProvider);
  return ref.watch(repositoryProvider).balances();
});

/// Assets, liabilities and their difference across all accounts.
final netWorthProvider = FutureProvider<NetWorth>((ref) async {
  ref.watch(dbRevisionProvider);
  return ref.watch(repositoryProvider).netWorth();
});

/// Entries in the selected month, newest first.
final monthTxnsProvider = FutureProvider<List<Txn>>((ref) async {
  ref.watch(dbRevisionProvider);
  final month = ref.watch(selectedMonthProvider);
  return ref.watch(repositoryProvider).txnsBetween(month, startOfNextMonth(month));
});

/// Income, expense and balance for a month.
final monthSummaryProvider = FutureProvider.autoDispose.family<PeriodSummary, DateTime>((ref, month) async {
  ref.watch(dbRevisionProvider);
  return ref.watch(repositoryProvider).summary(month, startOfNextMonth(month));
});

/// Totals per day of the selected month, by day number.
final dailySummariesProvider = FutureProvider<Map<int, PeriodSummary>>((ref) async {
  ref.watch(dbRevisionProvider);
  final month = ref.watch(selectedMonthProvider);
  return ref.watch(repositoryProvider).dailySummaries(month.year, month.month);
});

/// Totals per month of a year, by month number.
final yearSummariesProvider = FutureProvider.autoDispose.family<Map<int, PeriodSummary>, int>((ref, year) async {
  ref.watch(dbRevisionProvider);
  return ref.watch(repositoryProvider).monthlySummaries(year);
});

/// Spending or income per category for a month, largest first.
final categoryTotalsProvider = FutureProvider.autoDispose.family<List<CategoryTotal>, (DateTime, TxnType)>((
  ref,
  args,
) async {
  ref.watch(dbRevisionProvider);
  final (month, type) = args;
  return ref.watch(repositoryProvider).categoryTotals(month, startOfNextMonth(month), type);
});

/// Every entry that touches an account.
final accountTxnsProvider = FutureProvider.autoDispose.family<List<Txn>, int>((ref, accountId) async {
  ref.watch(dbRevisionProvider);
  return ref.watch(repositoryProvider).txnsBetween(DateTime(2000), DateTime(2100), accountId: accountId);
});

/// Entries in a category for a month.
final categoryMonthTxnsProvider = FutureProvider.autoDispose.family<List<Txn>, (int, DateTime)>((ref, args) async {
  ref.watch(dbRevisionProvider);
  final (categoryId, month) = args;
  return ref.watch(repositoryProvider).txnsBetween(month, startOfNextMonth(month), categoryId: categoryId);
});

/// Monthly limits by category id; the overall limit uses id 0.
final budgetsProvider = FutureProvider<Map<int, int>>((ref) async {
  ref.watch(dbRevisionProvider);
  return ref.watch(repositoryProvider).budgets();
});

/// Every recurring rule, active or paused.
final recurringRulesProvider = FutureProvider<List<RecurringRule>>((ref) async {
  ref.watch(dbRevisionProvider);
  return ref.watch(repositoryProvider).recurringRules();
});

/// Rules due now that wait for the user to confirm.
final dueRecurringProvider = FutureProvider<List<RecurringRule>>((ref) async {
  ref.watch(dbRevisionProvider);
  return ref.watch(recurringServiceProvider).dueForReview(DateTime.now());
});

/// The bridge to the Android notification listener. Overridden in tests.
final captureChannelProvider = Provider<CaptureChannel>((ref) => const CaptureChannel());

/// Turns raw notifications into captured payments.
final captureServiceProvider = Provider<CaptureService>(
  (ref) => CaptureService(ref.watch(repositoryProvider), channel: ref.watch(captureChannelProvider)),
);

/// Payments read from notifications, waiting for the user.
final pendingCapturesProvider = FutureProvider<List<CapturedPayment>>((ref) async {
  ref.watch(dbRevisionProvider);
  return ref.watch(repositoryProvider).capturedPayments(status: CaptureStatus.pending);
});

/// What a captured payment would be saved as: the guessed account and
/// category, with the payee as the note.
TxnDraft draftFromCapture(CapturedPayment c, Lookups l) {
  final income = c.direction == PaymentDirection.credit;
  final kind = income ? CategoryKind.income : CategoryKind.expense;
  final matcher = CategoryMatcher(l.categories);
  final category = matcher.match('${c.counterparty ?? ''} ${c.title} ${c.text}', kind);
  final hint = c.accountHint;
  final account =
      (hint == null ? null : l.activeAccounts.where((a) => a.name.contains(hint)).firstOrNull) ?? l.defaultAccount;
  return TxnDraft(
    type: income ? TxnType.income : TxnType.expense,
    amount: c.amount,
    date: c.postedAt,
    accountId: account?.id,
    categoryId: category?.id,
    note: c.counterparty ?? '',
    payee: c.counterparty,
    upiRef: c.upiRef,
    source: TxnSource.notification,
  );
}

/// Every write goes through here so screens refresh and reminders stay in
/// step with the recurring rules.
class FinanceActions {
  FinanceActions(this._ref);
  final Ref _ref;

  FinanceRepository get _repo => _ref.read(repositoryProvider);

  void _changed() => _ref.read(dbRevisionProvider.notifier).bump();

  /// Inserts or updates an entry and returns its id.
  Future<int> saveTxn(Txn t) async {
    final id = await _repo.saveTxn(t);
    _changed();
    return id;
  }

  /// Saves several entries, such as the drafts from one voice note.
  Future<void> saveTxns(List<Txn> txns) async {
    for (final t in txns) {
      await _repo.saveTxn(t);
    }
    _changed();
  }

  /// Writes an Excel or CSV import with the user's choices.
  Future<ImportResult> importPlan(ImportPlan plan, ImportMapping mapping) async {
    try {
      return await ImportService(_repo).commit(plan, mapping);
    } finally {
      _changed();
    }
  }

  /// Deletes an entry.
  Future<void> deleteTxn(int id) async {
    await _repo.deleteTxn(id);
    _changed();
  }

  /// Inserts or updates an account.
  Future<void> saveAccount(Account a) async {
    await _repo.saveAccount(a);
    _changed();
  }

  /// Inserts or updates a category.
  Future<void> saveCategory(Category c) async {
    await _repo.saveCategory(c);
    _changed();
  }

  /// Sets monthly limits; a null value removes that limit.
  Future<void> setBudgets(Map<int, int?> budgets) async {
    for (final e in budgets.entries) {
      await _repo.setBudget(e.key, e.value);
    }
    _changed();
  }

  /// Inserts or updates a recurring rule and reschedules reminders.
  Future<int> saveRule(RecurringRule r) async {
    final id = await _repo.saveRecurringRule(r);
    _changed();
    await syncReminders();
    return id;
  }

  /// Deletes a recurring rule and its reminder.
  Future<void> deleteRule(int id) async {
    await _repo.deleteRecurringRule(id);
    _changed();
    await syncReminders();
  }

  /// Records a due rule as an entry, optionally with the user's edits.
  Future<void> recordRule(RecurringRule r, {Txn? edited}) async {
    await _ref.read(recurringServiceProvider).record(r, edited: edited);
    _changed();
    await syncReminders();
  }

  /// Skips this occurrence of a rule and moves it to the next due date.
  Future<void> skipRule(RecurringRule r) async {
    await _ref.read(recurringServiceProvider).skip(r);
    _changed();
    await syncReminders();
  }

  /// Collects payments the notification listener saw since last time and
  /// returns how many are new. Returns 0 where there is no listener.
  Future<int> syncCaptures() async {
    try {
      final n = await _ref.read(captureServiceProvider).sync();
      if (n > 0) _changed();
      return n;
    } catch (_) {
      return 0;
    }
  }

  /// Saves a captured payment as an entry. Throws [DuplicatePaymentException]
  /// when its UPI reference is already recorded.
  Future<void> addCapture(CapturedPayment c, Txn txn) async {
    final id = await _repo.saveTxn(txn);
    await _repo.setCaptureStatus(c.id!, CaptureStatus.added, txnId: id);
    _changed();
  }

  /// Marks a capture handled after the user saved it through the form.
  Future<void> markCaptureAdded(CapturedPayment c) async {
    await _repo.setCaptureStatus(c.id!, CaptureStatus.added);
    _changed();
  }

  /// Marks a capture ignored, duplicate or pending again.
  Future<void> setCaptureStatus(CapturedPayment c, CaptureStatus status) async {
    await _repo.setCaptureStatus(c.id!, status);
    _changed();
  }

  /// Records auto-post rules that came due while the app was closed and
  /// returns how many were recorded.
  Future<int> runStartupTasks() async {
    final posted = await _ref.read(recurringServiceProvider).autoPostDue(DateTime.now());
    if (posted > 0) _changed();
    await syncReminders();
    return posted;
  }

  /// Inserts or updates a savings goal and returns its id.
  Future<int> saveGoal(Goal g) async {
    final id = await _repo.saveGoal(g);
    _changed();
    return id;
  }

  /// Deletes a goal and its history.
  Future<void> deleteGoal(int id) async {
    await _repo.deleteGoal(id);
    _changed();
  }

  /// Puts money into a goal (positive) or takes it out (negative).
  Future<void> addGoalEntry(GoalEntry e) async {
    await _repo.addGoalEntry(e);
    _changed();
  }

  Future<void> deleteGoalEntry(int id) async {
    await _repo.deleteGoalEntry(id);
    _changed();
  }

  /// Replaces all data with a backup, then refreshes every screen and the
  /// reminders.
  Future<void> restoreBackup(String backup) async {
    await _ref.read(backupServiceProvider).restore(backup);
    _changed();
    await syncReminders();
  }

  /// Reschedules reminders for the active rules. Best effort: a failure
  /// never blocks the write that triggered it.
  Future<void> syncReminders() async {
    try {
      final rules = await _repo.recurringRules(activeOnly: true);
      final categories = {for (final c in await _repo.categories(includeArchived: true)) c.id: c.name};
      await _ref
          .read(reminderServiceProvider)
          .rescheduleAll(rules, labelFor: (r) => r.note.isNotEmpty ? r.note : (categories[r.categoryId] ?? 'Payment'));
    } catch (e, st) {
      log('Could not reschedule reminders', error: e, stackTrace: st);
    }
  }
}

/// Savings goals that are still open, newest first.
final goalsProvider = FutureProvider<List<GoalProgress>>((ref) async {
  ref.watch(dbRevisionProvider);
  return ref.watch(repositoryProvider).goals();
});

/// Goals that were archived.
final archivedGoalsProvider = FutureProvider<List<GoalProgress>>((ref) async {
  ref.watch(dbRevisionProvider);
  return ref.watch(repositoryProvider).goals(archived: true);
});

/// One goal with what's saved toward it; null once it's deleted.
final goalProvider = FutureProvider.autoDispose.family<GoalProgress?, int>((ref, id) async {
  ref.watch(dbRevisionProvider);
  return ref.watch(repositoryProvider).goal(id);
});

/// The money put into and taken out of one goal.
final goalEntriesProvider = FutureProvider.autoDispose.family<List<GoalEntry>, int>((ref, id) async {
  ref.watch(dbRevisionProvider);
  return ref.watch(repositoryProvider).goalEntries(id);
});

/// See [FinanceActions].
final actionsProvider = Provider<FinanceActions>(FinanceActions.new);

/// Unlocks the app with the phone's screen lock.
final appLockServiceProvider = Provider<AppLockService>((ref) => AppLockService());

/// Whether the app asks for the phone's screen lock when opened. Kept on this
/// phone only, so restoring a backup never turns it on or off.
class AppLockSetting extends AsyncNotifier<bool> {
  static const key = 'app_lock';

  @override
  Future<bool> build() async => await ref.watch(repositoryProvider).setting(key) == 'on';

  /// Turns the lock on or off.
  Future<void> set(bool on) async {
    await ref.read(repositoryProvider).setSetting(key, on ? 'on' : null);
    state = AsyncData(on);
  }
}

/// See [AppLockSetting].
final appLockProvider = AsyncNotifierProvider<AppLockSetting, bool>(AppLockSetting.new);

/// Writes backups into the folder the user chose.
final backupFolderChannelProvider = Provider<BackupFolderChannel>((ref) => const BackupFolderChannel());

/// Weekly backups into a chosen folder.
final autoBackupServiceProvider = Provider<AutoBackupService>(
  (ref) => AutoBackupService(
    ref.watch(repositoryProvider),
    ref.watch(backupServiceProvider),
    ref.watch(backupFolderChannelProvider),
  ),
);

/// Where automatic backups go and how the last one went, with the actions
/// that change it.
class AutoBackup extends AsyncNotifier<AutoBackupStatus> {
  AutoBackupService get _service => ref.read(autoBackupServiceProvider);

  @override
  Future<AutoBackupStatus> build() => ref.watch(autoBackupServiceProvider).status();

  Future<void> _refresh() async => state = AsyncData(await _service.status());

  /// Picks a folder and backs up into it. Returns false when none was chosen.
  Future<bool> chooseFolder() async {
    try {
      return await _service.chooseFolder(DateTime.now());
    } finally {
      await _refresh();
    }
  }

  Future<void> turnOff() async {
    await _service.turnOff();
    await _refresh();
  }

  Future<void> backUpNow() async {
    try {
      await _service.backUp(DateTime.now());
    } finally {
      await _refresh();
    }
  }

  /// Backs up if a week has passed. Throws [AutoBackupException] on failure.
  Future<bool> runIfDue() async {
    try {
      return await _service.runIfDue(DateTime.now());
    } finally {
      await _refresh();
    }
  }
}

/// See [AutoBackup].
final autoBackupProvider = AsyncNotifierProvider<AutoBackup, AutoBackupStatus>(AutoBackup.new);

/// What a month's entries show against the month before.
final insightsProvider = FutureProvider.autoDispose.family<MonthInsights, DateTime>((ref, month) async {
  ref.watch(dbRevisionProvider);
  final repo = ref.watch(repositoryProvider);
  final previous = DateTime(month.year, month.month - 1);
  final categories = await repo.categories(includeArchived: true);
  return InsightsService.build(
    month: month,
    now: DateTime.now(),
    thisMonth: await repo.txnsBetween(month, startOfNextMonth(month)),
    lastMonth: await repo.txnsBetween(previous, month),
    categoryNames: {for (final c in categories) c.id!: c.name},
  );
});
