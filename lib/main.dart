import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import 'data/db/app_database.dart';
import 'data/finance_repository.dart';
import 'state/providers.dart';
import 'ui/home_shell.dart';
import 'ui/lock/app_lock_gate.dart';
import 'ui/theme.dart';

/// Opens the database and starts the app.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'en_IN';
  await initializeDateFormatting('en_IN');
  final database = await AppDatabase.open();
  runApp(
    ProviderScope(
      overrides: [repositoryProvider.overrideWithValue(FinanceRepository(database))],
      child: const FinanceApp(),
    ),
  );
}

/// The app root: theme, locale, the app lock and the home shell.
class FinanceApp extends StatelessWidget {
  const FinanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Finance Tracker',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      builder: (context, child) => AppLockGate(child: child!),
      home: const HomeShell(),
    );
  }
}
