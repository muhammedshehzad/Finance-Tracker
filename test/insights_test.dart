import 'package:finance_tracker/data/models/txn.dart';
import 'package:finance_tracker/services/insights_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

const food = 1, rent = 2, shopping = 3, salary = 4;
const names = {food: 'Food', rent: 'Rent', shopping: 'Shopping', salary: 'Salary'};

Txn spend(int rupees, DateTime date, int category, {String? payee}) =>
    Txn(type: TxnType.expense, amount: rupees * 100, date: date, accountId: 1, categoryId: category, payee: payee);

Txn earn(int rupees, DateTime date) =>
    Txn(type: TxnType.income, amount: rupees * 100, date: date, accountId: 1, categoryId: salary);

void main() {
  setUpAll(() async {
    Intl.defaultLocale = 'en_IN';
    await initializeDateFormatting('en_IN');
  });

  Insight? of(MonthInsights m, InsightKind kind) => m.items.where((i) => i.kind == kind).firstOrNull;

  test('a month in progress is compared with the same days of last month', () {
    final now = DateTime(2026, 11, 10, 20);
    final m = InsightsService.build(
      month: DateTime(2026, 11),
      now: now,
      thisMonth: [spend(8000, DateTime(2026, 11, 3), food)],
      lastMonth: [
        spend(10000, DateTime(2026, 10, 4), food),
        // After the 10th, so left out: comparing it would flatter November.
        spend(30000, DateTime(2026, 10, 25), shopping),
      ],
      categoryNames: names,
    );
    final pace = of(m, InsightKind.pace)!;
    expect(pace.title, 'You\'ve spent 20% less than at this point in Oct');
    expect(pace.detail, '₹8,000 so far, against ₹10,000 by 10 Oct.');
    expect(pace.tone, InsightTone.good);
    expect(m.comparedThroughDay, 10);
    expect(m.headline, same(pace));
  });

  test('a finished month is compared whole', () {
    final m = InsightsService.build(
      month: DateTime(2026, 10),
      now: DateTime(2026, 11, 27),
      thisMonth: [spend(12000, DateTime(2026, 10, 30), food)],
      lastMonth: [spend(10000, DateTime(2026, 9, 30), food)],
      categoryNames: names,
    );
    expect(of(m, InsightKind.pace)!.title, 'You spent 20% more than in Sept');
    expect(of(m, InsightKind.pace)!.tone, InsightTone.bad);
    expect(m.comparedThroughDay, isNull);
  });

  test('the 31st is compared with the end of a 30 day month', () {
    final m = InsightsService.build(
      month: DateTime(2026, 12),
      now: DateTime(2026, 12, 31, 9),
      thisMonth: [spend(1000, DateTime(2026, 12, 5), food)],
      lastMonth: [spend(1000, DateTime(2026, 11, 30), food)],
      categoryNames: names,
    );
    expect(of(m, InsightKind.pace)!.detail, '₹1,000 so far, against ₹1,000 by 30 Nov.');
  });

  test('names the category that rose most and the one that fell most, ignoring small moves', () {
    final d = DateTime(2026, 10, 5);
    final p = DateTime(2026, 9, 5);
    final m = InsightsService.build(
      month: DateTime(2026, 10),
      now: DateTime(2026, 11, 2),
      thisMonth: [spend(9200, d, food), spend(1000, d, shopping), spend(15100, d, rent)],
      lastMonth: [spend(6800, p, food), spend(4100, p, shopping), spend(15000, p, rent)],
      categoryNames: names,
    );
    final up = of(m, InsightKind.categoryUp)!;
    expect(up.title, 'Food is up ₹2,400');
    expect(up.detail, '₹9,200 against ₹6,800 in Sept, 35% more.');
    expect(up.categoryId, food);
    expect(of(m, InsightKind.categoryDown)!.title, 'Shopping is down ₹3,100');
    expect(m.items.where((i) => i.title.startsWith('Rent')), isEmpty, reason: '₹100 on ₹15,000 is noise');
  });

  test('says what was kept of the income, or how far spending went over', () {
    final d = DateTime(2026, 10, 1);
    final kept = InsightsService.build(
      month: DateTime(2026, 10),
      now: DateTime(2026, 11, 2),
      thisMonth: [earn(50000, d), spend(38000, d, rent)],
      lastMonth: const [],
      categoryNames: names,
    );
    expect(of(kept, InsightKind.savings)!.title, 'You kept 24% of what came in');
    expect(of(kept, InsightKind.savings)!.detail, '₹50,000 in, ₹38,000 out.');
    expect(of(kept, InsightKind.pace), isNull, reason: 'nothing last month to compare with');

    final over = InsightsService.build(
      month: DateTime(2026, 10),
      now: DateTime(2026, 11, 2),
      thisMonth: [earn(30000, d), spend(34000, d, rent)],
      lastMonth: const [],
      categoryNames: names,
    );
    expect(of(over, InsightKind.savings)!.title, 'You spent ₹4,000 more than came in');
    expect(of(over, InsightKind.savings)!.tone, InsightTone.bad);
  });

  test('daily average projects the month only once a week has passed', () {
    final early = InsightsService.build(
      month: DateTime(2026, 11),
      now: DateTime(2026, 11, 3),
      thisMonth: [spend(3000, DateTime(2026, 11, 2), food)],
      lastMonth: const [],
      categoryNames: names,
    );
    expect(of(early, InsightKind.daily)!.title, '₹1,000 a day on average');
    expect(of(early, InsightKind.daily)!.detail, 'Over the first 3 days of Nov.');

    final later = InsightsService.build(
      month: DateTime(2026, 11),
      now: DateTime(2026, 11, 10),
      thisMonth: [spend(12000, DateTime(2026, 11, 2), food)],
      lastMonth: const [],
      categoryNames: names,
    );
    expect(of(later, InsightKind.daily)!.detail, 'At this pace, about ₹36,000 by the end of Nov.');
  });

  test('finds the biggest spend and the payee paid most often', () {
    final d = DateTime(2026, 10, 3);
    final m = InsightsService.build(
      month: DateTime(2026, 10),
      now: DateTime(2026, 11, 2),
      thisMonth: [
        spend(12000, d, rent, payee: 'Landlord'),
        for (var i = 0; i < 4; i++) spend(300, d.add(Duration(days: i)), food, payee: i.isEven ? 'Swiggy' : 'swiggy '),
        spend(200, d, food, payee: 'Chai Point'),
      ],
      lastMonth: const [],
      categoryNames: names,
    );
    expect(of(m, InsightKind.biggest)!.title, 'Biggest spend: ₹12,000');
    expect(of(m, InsightKind.biggest)!.detail, 'Landlord on 3 Oct.');
    expect(of(m, InsightKind.payee)!.title, 'Swiggy: 4 payments');
    expect(of(m, InsightKind.payee)!.detail, '₹1,200 in all this month.');
  });

  test('transfers and future months give nothing', () {
    final transfer = Txn(
      type: TxnType.transfer,
      amount: 500000,
      date: DateTime(2026, 10, 3),
      accountId: 1,
      toAccountId: 2,
    );
    final m = InsightsService.build(
      month: DateTime(2026, 10),
      now: DateTime(2026, 11, 2),
      thisMonth: [transfer],
      lastMonth: const [],
      categoryNames: names,
    );
    expect(m.items, isEmpty);
    expect(
      InsightsService.build(
        month: DateTime(2027, 1),
        now: DateTime(2026, 11, 2),
        thisMonth: const [],
        lastMonth: const [],
        categoryNames: names,
      ).items,
      isEmpty,
    );
  });
}
