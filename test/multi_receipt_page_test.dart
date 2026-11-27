import 'package:finance_tracker/data/db/app_database.dart';
import 'package:finance_tracker/data/finance_repository.dart';
import 'package:finance_tracker/data/models/account.dart';
import 'package:finance_tracker/data/models/category.dart';
import 'package:finance_tracker/data/models/txn.dart';
import 'package:finance_tracker/services/receipt_parser.dart';
import 'package:finance_tracker/services/receipt_scanner.dart';
import 'package:finance_tracker/state/providers.dart';
import 'package:finance_tracker/ui/entry/multi_receipt_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A Google Pay history with three payments, one of them already saved.
void main() {
  sqfliteFfiInit();

  testWidgets('saves the ticked payments and leaves the recorded one out', (tester) async {
    late FinanceRepository repo;
    final day = DateTime(2026, 11, 25);
    await tester.runAsync(() async {
      Intl.defaultLocale = 'en_IN';
      await initializeDateFormatting('en_IN');
      repo = FinanceRepository(await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath));
      final bank = (await repo.accounts()).firstWhere((a) => a.kind == AccountKind.bank).id!;
      final food = (await repo.categories(kind: CategoryKind.expense)).first.id!;
      await repo.saveTxn(
        Txn(
          type: TxnType.expense,
          amount: 400000,
          date: day.add(const Duration(hours: 17)),
          accountId: bank,
          categoryId: food,
          payee: 'Fathimathul Mushirif',
        ),
      );
    });

    final scanned = ScannedReceipt(
      imagePath: '/nonexistent/receipt.png',
      results: [
        ReceiptParseResult(
          amountPaise: 400000,
          payee: 'Fathimathul Mushirif',
          date: day,
          hasTime: false,
          direction: ReceiptDirection.paid,
          rawText: '',
        ),
        ReceiptParseResult(amountPaise: 9000, payee: 'Swiggy', date: day, hasTime: false, rawText: ''),
        ReceiptParseResult(
          amountPaise: 150000,
          payee: 'Ameen K',
          date: day,
          hasTime: false,
          direction: ReceiptDirection.received,
          rawText: '',
        ),
      ],
    );

    Future<void> settle() async {
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(home: MultiReceiptPage(scanned: scanned)),
      ),
    );
    await settle();

    expect(find.text('3 payments found'), findsOneWidget);
    expect(find.textContaining('Looks already recorded'), findsOneWidget);
    expect(find.text('Save 2 entries'), findsOneWidget);
    expect(find.text('+₹1,500'), findsOneWidget);

    await tester.tap(find.text('Save 2 entries'));
    await settle();

    final saved = await tester.runAsync(() => repo.allTxns());
    expect(saved!.length, 3);
    expect(saved.where((t) => t.type == TxnType.income).single.amount, 150000);
    expect(saved.where((t) => t.payee == 'Swiggy').single.source, TxnSource.screenshot);
  });
}
