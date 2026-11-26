import 'dart:convert';
import 'dart:typed_data';

import 'package:finance_tracker/data/db/app_database.dart';
import 'package:finance_tracker/data/finance_repository.dart';
import 'package:finance_tracker/data/models/txn.dart';
import 'package:finance_tracker/state/providers.dart';
import 'package:finance_tracker/ui/import/import_page.dart';
import 'package:finance_tracker/ui/theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  testWidgets('imports this year from a Money Manager file, and a second run adds nothing', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final y = DateTime.now().year;
    final csv =
        '''
Period,Accounts,Category,Subcategory,Note,INR,Income/Expense,Description,Amount,Currency,Accounts
02/01/$y 09:12:00,Accounts,Food,Breakfast,Breakfast,8,Exp.,,8,INR,8
03/01/$y 13:40:00,Accounts,Food,,Lunch,90,Exp.,,90,INR,90
04/01/$y 18:05:00,Accounts,Credit Card Bill,,HDFC bill,"16,359.00",Exp.,,16359,INR,16359
05/01/$y 10:00:00,Accounts,Salary,,January,"32,185",Income,,32185,INR,32185
06/01/$y 20:00:00,Accounts,Cash,,ATM,500,Transfer-Out,,500,INR,500
06/01/$y 20:00:00,Cash,Accounts,,ATM,500,Transfer-In,,500,INR,500
31/12/${y - 1} 21:00:00,Accounts,Food,,Dinner,300,Exp.,,300,INR,300
''';
    final file = (name: 'Money Manager.csv', bytes: Uint8List.fromList(utf8.encode(csv)));

    late FinanceRepository repo;
    await tester.runAsync(() async {
      Intl.defaultLocale = 'en_IN';
      await initializeDateFormatting('en_IN');
      repo = FinanceRepository(await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath));
    });

    Future<void> settle() async {
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(tester.takeException(), isNull);
    }

    Future<void> runImport() async {
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [repositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            theme: buildTheme(Brightness.light),
            home: ImportPage(initialFile: file),
          ),
        ),
      );
      await settle();
      expect(find.text('5 entries'), findsOneWidget, reason: 'this year only, transfer pair merged');
      await tester.tap(find.text('Import 5 entries'));
      await settle();
    }

    await runImport();
    expect(find.text('Imported 5 entries'), findsOneWidget);
    final saved = await tester.runAsync(repo.allTxns);
    expect(saved, hasLength(5));
    expect(saved!.every((t) => t.source == TxnSource.imported), isTrue);
    expect(saved.where((t) => t.type == TxnType.transfer), hasLength(1));

    await runImport();
    expect(find.text('Imported 0 entries'), findsOneWidget);
    expect(find.textContaining('5 entries were already in the app'), findsOneWidget);
    expect(await tester.runAsync(repo.allTxns), hasLength(5));
  });
}
