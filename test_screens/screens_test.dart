/// Renders each screen to PNG with real fonts, in light and dark, for
/// design review. Run `flutter test test_screens --update-goldens`; the
/// images land in test_screens/out/.
library;

import 'dart:convert';
import 'dart:io';

import 'package:finance_tracker/data/db/app_database.dart';
import 'package:finance_tracker/data/finance_repository.dart';
import 'package:finance_tracker/data/models/account.dart';
import 'package:finance_tracker/data/models/captured_payment.dart';
import 'package:finance_tracker/data/models/goal.dart';
import 'package:finance_tracker/data/models/recurring_rule.dart';
import 'package:finance_tracker/data/models/txn.dart';
import 'package:finance_tracker/services/capture/capture_channel.dart';
import 'package:finance_tracker/services/capture/notification_parser.dart';
import 'package:finance_tracker/state/providers.dart';
import 'package:finance_tracker/ui/backup/auto_backup_page.dart';
import 'package:finance_tracker/ui/capture/capture_settings_page.dart';
import 'package:finance_tracker/ui/capture/captured_payments_page.dart';
import 'package:finance_tracker/ui/goals/goals_page.dart';
import 'package:finance_tracker/ui/home_shell.dart';
import 'package:finance_tracker/ui/import/import_page.dart';
import 'package:finance_tracker/ui/stats/insights_page.dart';
import 'package:finance_tracker/ui/theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _fonts = '/opt/sdk/flutter/bin/cache/artifacts/material_fonts';

Future<void> _load(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await loader.load();
}

Future<FinanceRepository> _seed() async {
  final repo = FinanceRepository(
    await AppDatabase.open(factory: databaseFactoryFfi, path: '${Directory.systemTemp.createTempSync().path}/t.db'),
  );
  final acc = {for (final a in await repo.accounts()) a.kind: a};
  await repo.saveAccount(acc[AccountKind.bank]!.copyWith(openingBalance: 4250000));
  await repo.saveAccount(acc[AccountKind.cash]!.copyWith(openingBalance: 320000));
  await repo.saveAccount(acc[AccountKind.creditCard]!.copyWith(openingBalance: -1845000, creditLimit: 10000000));
  final cats = {for (final c in await repo.categories()) c.name: c.id!};
  final bank = acc[AccountKind.bank]!.id!, cash = acc[AccountKind.cash]!.id!, card = acc[AccountKind.creditCard]!.id!;
  final now = DateTime.now();
  DateTime d(int daysAgo, int h) => DateTime(now.year, now.month, now.day - daysAgo, h, 15);
  Future<void> e(
    String cat,
    int rupees,
    int ago,
    String note, {
    int? account,
    TxnSource src = TxnSource.manual,
    String? upi,
  }) => repo.saveTxn(
    Txn(
      type: TxnType.expense,
      amount: rupees * 100,
      date: d(ago, 13),
      accountId: account ?? bank,
      categoryId: cats[cat],
      note: note,
      source: src,
      upiRef: upi,
    ),
  );
  await repo.saveTxn(
    Txn(
      type: TxnType.income,
      amount: 8500000,
      date: d(now.day - 1, 10),
      accountId: bank,
      categoryId: cats['Salary'],
      note: 'November salary',
    ),
  );
  await e('Rent', 18000, now.day - 2, 'Room rent');
  await e('Food', 240, 0, 'Lunch', account: cash, src: TxnSource.voice);
  await e('Transport', 120, 0, 'Auto to office', account: cash, src: TxnSource.voice);
  await e('Groceries', 1864, 0, 'DMart', src: TxnSource.screenshot, upi: '533412987654');
  await e('Food', 459, 1, 'Swiggy dinner', account: card);
  await e('Bills & recharge', 349, 1, 'Jio recharge', src: TxnSource.screenshot, upi: '533412000111');
  await e('Shopping', 2499, 3, 'Shoes', account: card);
  await e('Health', 680, 4, 'Pharmacy');
  await repo.saveTxn(
    Txn(type: TxnType.transfer, amount: 1200000, date: d(2, 18), accountId: bank, toAccountId: card, note: 'Card bill'),
  );
  await repo.saveTxn(
    Txn(
      type: TxnType.transfer,
      amount: 500000,
      date: d(3, 18),
      accountId: bank,
      toAccountId: acc[AccountKind.receivable]!.id,
      note: 'Lent to Arif',
    ),
  );
  // Last month, for insights.
  DateTime last(int day) => DateTime(now.year, now.month - 1, day.clamp(1, 28), 13);
  for (final (cat, rupees, day) in [
    ('Rent', 18000, 2),
    ('Food', 1900, 5),
    ('Shopping', 6400, 8),
    ('Groceries', 2300, 10),
    ('Food', 820, 20),
  ]) {
    await repo.saveTxn(
      Txn(type: TxnType.expense, amount: rupees * 100, date: last(day), accountId: bank, categoryId: cats[cat]),
    );
  }
  final trip = await repo.saveGoal(
    Goal(name: 'Goa trip', emoji: '✈️', target: 4000000, targetDate: DateTime(now.year + 1, 3, 15), createdAt: now),
  );
  await repo.addGoalEntry(GoalEntry(goalId: trip, amount: 1500000, date: d(20, 9), note: 'Bonus'));
  await repo.addGoalEntry(GoalEntry(goalId: trip, amount: 300000, date: d(2, 9)));
  final fund = await repo.saveGoal(
    Goal(name: 'Emergency fund', emoji: '🛟', target: 20000000, createdAt: now.subtract(const Duration(days: 1))),
  );
  await repo.addGoalEntry(GoalEntry(goalId: fund, amount: 6200000, date: d(10, 9)));
  await repo.setBudget(FinanceRepository.overallBudgetKey, 4000000);
  await repo.setBudget(cats['Food']!, 600000);
  await repo.setBudget(cats['Shopping']!, 200000);
  await repo.saveRecurringRule(
    RecurringRule(
      type: TxnType.expense,
      amount: 79900,
      accountId: card,
      categoryId: cats['Bills & recharge'],
      note: 'Netflix',
      frequency: Frequency.monthly,
      startDate: d(0, 9),
      nextDue: d(0, 9),
    ),
  );
  await repo.saveRecurringRule(
    RecurringRule(
      type: TxnType.expense,
      amount: 1800000,
      accountId: bank,
      categoryId: cats['Rent'],
      note: 'Room rent',
      frequency: Frequency.monthly,
      startDate: DateTime(now.year, now.month + 1, 1, 9),
      nextDue: DateTime(now.year, now.month + 1, 1, 9),
    ),
  );
  Future<void> cap(
    String key,
    String pkg,
    int rupees,
    String who,
    int minsAgo, {
    bool credit = false,
    String? hint,
    String? ref,
    int? pair,
  }) => repo.insertCaptured(
    CapturedPayment(
      key: key,
      package: pkg,
      postedAt: now.subtract(Duration(minutes: minsAgo)),
      direction: credit ? PaymentDirection.credit : PaymentDirection.debit,
      amount: rupees * 100,
      counterparty: who,
      accountHint: hint,
      upiRef: ref,
      possibleDuplicateOf: pair,
    ),
  );
  await cap('a', 'com.google.android.apps.nbu.paisa.user', 180, 'Chai Point', 95);
  await cap('b', 'com.phonepe.app', 650, 'Ravi Electricals', 60);
  await cap('c', 'com.google.android.apps.nbu.paisa.user', 2000, 'Arif Khan', 30, credit: true);
  await cap(
    'd',
    'com.google.android.apps.messaging',
    180,
    'chaipoint@ybl',
    93,
    hint: '1234',
    ref: '533499990001',
    pair: 1,
  );
  await repo.setSetting('drive_backup_on', 'on');
  await repo.setSetting('drive_backup_account', 'you@gmail.com');
  await repo.setSetting('drive_backup_last', DateTime.now().subtract(const Duration(days: 2)).toIso8601String());
  return repo;
}

class _FakeChannel extends CaptureChannel {
  @override
  bool get supported => true;
  @override
  Future<bool> isEnabled() async => true;
  @override
  Future<Set<String>?> packages() async => null;
  @override
  Future<List<RawNotification>> drain() async => const [];
}

var _fontsLoaded = false;

void main() {
  sqfliteFfiInit();

  for (final dark in [false, true]) {
    testWidgets('screens ${dark ? 'dark' : 'light'}', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      // Draw screens as a finger sees them, without keyboard focus rings.
      FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
      // Tests draw shadows as solid outlines; draw real ones as a phone does.
      debugDisableShadows = false;
      addTearDown(() => debugDisableShadows = true);
      late FinanceRepository repo;
      await tester.runAsync(() async {
        Intl.defaultLocale = 'en_IN';
        await initializeDateFormatting('en_IN');
        if (!_fontsLoaded) {
          _fontsLoaded = true;
          await _load('Roboto', ['$_fonts/Roboto-Regular.ttf', '$_fonts/Roboto-Medium.ttf', '$_fonts/Roboto-Bold.ttf']);
          await _load('MaterialIcons', ['$_fonts/MaterialIcons-Regular.otf']);
          await _load('NotoColorEmoji', ['/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf']);
        }
        repo = await _seed();
      });

      Future<void> settle() async {
        for (var i = 0; i < 16; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump(const Duration(milliseconds: 60));
        }
      }

      final suffix = dark ? 'dark' : 'light';
      Future<void> shot(String name) async {
        await settle();
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/${name}_$suffix.png'));
      }

      ThemeData t(Brightness b) => buildTheme(b).copyWith(
        textTheme: buildTheme(b).textTheme.apply(fontFamily: 'Roboto', fontFamilyFallback: ['NotoColorEmoji']),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(repo),
            captureChannelProvider.overrideWithValue(_FakeChannel()),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: t(dark ? Brightness.dark : Brightness.light),
            home: const HomeShell(),
          ),
        ),
      );
      await shot('01_daily');
      for (final (i, tab) in [(2, 'Calendar'), (3, 'Monthly'), (4, 'Budget')]) {
        await tester.tap(find.text(tab).first);
        await shot('0${i}_${tab.toLowerCase()}');
      }
      await tester.tap(find.text('Daily').first);
      await settle();
      await tester.tap(find.text('Stats').last);
      await shot('05_stats');
      await tester.tap(find.text('Accounts').last);
      await shot('06_accounts');
      await tester.tap(find.text('More').last);
      await shot('07_more');
      await tester.tap(find.text('Recurring payments').first);
      await shot('08_recurring');
      await tester.pageBack();
      await settle();
      await tester.tap(find.text('Categories').first);
      await shot('09_categories');
      await tester.pageBack();
      await settle();
      await tester.tap(find.text('Transactions').last);
      await settle();
      await tester.tap(find.byTooltip('Add entry'));
      await shot('10_form');
      await tester.pageBack();
      await settle();
      await tester.tap(find.text('DMart').first);
      await shot('11_edit_screenshot_entry');
      await tester.pageBack();
      await settle();

      final nav = Navigator.of(tester.element(find.byType(HomeShell)));
      nav.push(MaterialPageRoute<void>(builder: (_) => const ImportPage()));
      await shot('12_import_intro');
      nav.pop();
      await settle();
      final y = DateTime.now().year;
      final rows = StringBuffer(
        'Period,Accounts,Category,Subcategory,Note,INR,Income/Expense,Description,Amount,Currency,Accounts\n',
      );
      final cats = ['Food', 'Transport', 'Akhira', 'Mobile settlement', 'Lended money', 'Credit Card Bill', 'Rent'];
      for (var m = 1; m <= 11; m++) {
        rows.writeln(
          '01/${m.toString().padLeft(2, '0')}/$y 10:00:00,Accounts,Salary,,Salary,"32,185",Income,,32185,INR,32185',
        );
        for (var d = 2; d <= 27; d += 3) {
          final c = cats[(d + m) % cats.length];
          rows.writeln(
            '${d.toString().padLeft(2, '0')}/${m.toString().padLeft(2, '0')}/$y 13:00:00,${d % 4 == 0 ? 'Cash' : 'Accounts'},$c,,$c,${90 + d * 7},Exp.,,0,INR,0',
          );
        }
      }
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => ImportPage(
            initialFile: (name: 'Money Manager 2026.csv', bytes: Uint8List.fromList(utf8.encode(rows.toString()))),
          ),
        ),
      );
      await shot('13_import_review');
      await tester.drag(find.byType(ListView).last, const Offset(0, -900));
      await shot('14_import_categories');
      await tester.tap(find.textContaining('Import ').last);
      await shot('15_import_done');
      nav.pop();
      await settle();
      nav.push(MaterialPageRoute<void>(builder: (_) => const CapturedPaymentsPage()));
      await shot('16_captured_payments');
      nav.push(MaterialPageRoute<void>(builder: (_) => const CaptureSettingsPage()));
      await shot('17_capture_settings');
      nav.push(MaterialPageRoute<void>(builder: (_) => const GoalsPage()));
      await shot('18_goals');
      await tester.tap(find.text('Goa trip'));
      await shot('19_goal_detail');
      await tester.tap(find.widgetWithText(FilledButton, 'Put in'));
      await shot('20_goal_put_in');
      nav.pop();
      await settle();
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => InsightsPage(month: DateTime(DateTime.now().year, DateTime.now().month)),
        ),
      );
      await shot('21_insights');
      nav.push(MaterialPageRoute<void>(builder: (_) => const AutoBackupPage()));
      await shot('22_auto_backup');
      await tester.drag(find.byType(ListView).last, const Offset(0, -420));
      await shot('23_drive_backup');
    });
  }
}
