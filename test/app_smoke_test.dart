import 'package:finance_tracker/data/db/app_database.dart';
import 'package:finance_tracker/data/finance_repository.dart';
import 'package:finance_tracker/data/models/account.dart';
import 'package:finance_tracker/data/models/category.dart';
import 'package:finance_tracker/data/models/txn.dart';
import 'package:finance_tracker/main.dart';
import 'package:finance_tracker/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Boots the real app on an in-memory database and opens every screen once,
/// so layout errors and provider wiring mistakes fail here instead of on the
/// phone. Plugins (camera, ML Kit, speech, notifications) are not exercised.
void main() {
  sqfliteFfiInit();

  testWidgets('every screen opens with data in it', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    late FinanceRepository repo;
    await tester.runAsync(() async {
      Intl.defaultLocale = 'en_IN';
      await initializeDateFormatting('en_IN');
      repo = FinanceRepository(await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath));
      final accounts = await repo.accounts();
      final bank = accounts.firstWhere((a) => a.kind == AccountKind.bank).id!;
      final food = (await repo.categories(kind: CategoryKind.expense)).first.id!;
      final salary = (await repo.categories(kind: CategoryKind.income)).first.id!;
      final now = DateTime.now();
      await repo.saveTxn(
        Txn(type: TxnType.expense, amount: 45000, date: now, accountId: bank, categoryId: food, note: 'Lunch'),
      );
      await repo.setBudget(FinanceRepository.overallBudgetKey, 2000000);
      await repo.setBudget(food, 300000);
      await repo.saveTxn(Txn(type: TxnType.income, amount: 5000000, date: now, accountId: bank, categoryId: salary));
    });

    Future<void> settle() async {
      for (var i = 0; i < 16; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      final e = tester.takeException();
      expect(e, isNull);
    }

    await tester.pumpWidget(
      ProviderScope(overrides: [repositoryProvider.overrideWithValue(repo)], child: const FinanceApp()),
    );
    await settle();
    expect(find.text('Lunch'), findsWidgets);

    for (final tab in ['Calendar', 'Monthly', 'Budget', 'Daily']) {
      await tester.tap(find.text(tab).first);
      await settle();
    }

    for (final dest in ['Stats', 'Accounts', 'More']) {
      await tester.tap(find.text(dest).last);
      await settle();
    }
    expect(find.text('Recurring payments'), findsOneWidget);

    for (final page in ['Recurring payments', 'Categories', 'Budgets']) {
      await tester.tap(find.text(page).first);
      await settle();
      await tester.pageBack();
      await settle();
    }

    await tester.tap(find.text('Transactions').last);
    await settle();
    await tester.tap(find.byTooltip('Add entry'));
    await settle();
    expect(find.text('Save'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
