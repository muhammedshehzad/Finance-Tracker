import '../data/finance_repository.dart';
import '../data/models/recurring_rule.dart';
import '../data/models/txn.dart';
import 'recurring_engine.dart';

/// Applies recurring rules to the database.
///
/// Rules marked auto-post are recorded on app start. All others wait in
/// "Due now" until you record or skip them, so nothing is entered without
/// your confirmation unless you chose that for the rule.
class RecurringService {
  RecurringService(this.repo, {this.engine = const RecurringEngine()});

  final FinanceRepository repo;
  final RecurringEngine engine;

  /// Records every due occurrence of auto-post rules. Returns how many
  /// transactions were added.
  Future<int> autoPostDue(DateTime now) async {
    var posted = 0;
    for (final rule in await repo.recurringRules(activeOnly: true)) {
      if (!rule.autoPost) continue;
      var current = rule;
      for (final date in engine.dueOccurrences(rule, now)) {
        final next = engine.advance(current, date);
        await repo.postRecurring(
          current,
          engine.txnFor(current, date),
          next,
          deactivate: engine.isPastEnd(current, next),
        );
        current = current.copyWith(nextDue: next);
        posted++;
      }
    }
    return posted;
  }

  /// Rules that wait for confirmation and are due today or earlier.
  Future<List<RecurringRule>> dueForReview(DateTime now) async {
    final rules = await repo.recurringRules(activeOnly: true);
    return rules.where((r) => !r.autoPost && engine.isDue(r, now)).toList();
  }

  /// Records the rule's current occurrence (optionally as edited by the user)
  /// and moves it on to the next date.
  Future<void> record(RecurringRule rule, {Txn? edited}) async {
    final txn = (edited ?? engine.txnFor(rule, rule.nextDue)).copyWith(
      source: TxnSource.recurring,
      recurringId: rule.id,
    );
    final next = engine.advance(rule, rule.nextDue);
    await repo.postRecurring(rule, txn, next, deactivate: engine.isPastEnd(rule, next));
  }

  /// Moves the rule on without recording anything, e.g. rent waived this month.
  Future<void> skip(RecurringRule rule) async {
    final next = engine.advance(rule, rule.nextDue);
    await repo.saveRecurringRule(rule.copyWith(nextDue: next, active: !engine.isPastEnd(rule, next)));
  }
}
