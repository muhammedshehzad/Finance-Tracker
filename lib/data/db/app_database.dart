import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'seed.dart';

/// Opens the local SQLite database and owns its schema.
///
/// All finance data lives on the device. Bump [schemaVersion] and add a step
/// to [_migrate] whenever the schema changes.
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static const schemaVersion = 3;
  static const fileName = 'finance_tracker.db';

  static Future<AppDatabase> open({DatabaseFactory? factory, String? path}) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), fileName);
    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          await _createV1(db);
          await _createV2(db);
          await _createV3(db);
          await seedDefaults(db);
        },
        onUpgrade: _migrate,
      ),
    );
    return AppDatabase._(db);
  }

  static Future<void> _createV1(Database db) async {
    final batch = db.batch();
    batch.execute('''
      CREATE TABLE accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        kind TEXT NOT NULL,
        opening_balance INTEGER NOT NULL DEFAULT 0,
        credit_limit INTEGER,
        archived INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0
      )''');
    batch.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        kind TEXT NOT NULL,
        icon TEXT NOT NULL,
        color INTEGER NOT NULL,
        keywords TEXT NOT NULL DEFAULT '',
        archived INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0
      )''');
    batch.execute('''
      CREATE TABLE recurring_rules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        amount INTEGER NOT NULL,
        account_id INTEGER NOT NULL REFERENCES accounts(id),
        category_id INTEGER REFERENCES categories(id),
        to_account_id INTEGER REFERENCES accounts(id),
        note TEXT NOT NULL DEFAULT '',
        frequency TEXT NOT NULL,
        interval INTEGER NOT NULL DEFAULT 1,
        start_date INTEGER NOT NULL,
        end_date INTEGER,
        next_due INTEGER NOT NULL,
        auto_post INTEGER NOT NULL DEFAULT 0,
        remind_days_before INTEGER NOT NULL DEFAULT 1,
        active INTEGER NOT NULL DEFAULT 1
      )''');
    batch.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        amount INTEGER NOT NULL CHECK (amount > 0),
        date INTEGER NOT NULL,
        account_id INTEGER NOT NULL REFERENCES accounts(id),
        category_id INTEGER REFERENCES categories(id),
        to_account_id INTEGER REFERENCES accounts(id),
        note TEXT NOT NULL DEFAULT '',
        description TEXT NOT NULL DEFAULT '',
        source TEXT NOT NULL DEFAULT 'manual',
        attachment_path TEXT,
        upi_ref TEXT,
        payee TEXT,
        recurring_id INTEGER REFERENCES recurring_rules(id) ON DELETE SET NULL
      )''');
    batch.execute('CREATE INDEX idx_txn_date ON transactions(date)');
    batch.execute('CREATE UNIQUE INDEX idx_txn_upi_ref ON transactions(upi_ref) WHERE upi_ref IS NOT NULL');
    batch.execute('''
      CREATE TABLE budgets (
        category_id INTEGER PRIMARY KEY,
        amount INTEGER NOT NULL
      )''');
    await batch.commit(noResult: true);
  }

  /// v2: payments read from UPI app and bank SMS notifications, waiting
  /// for the user to add or ignore them.
  static Future<void> _createV2(Database db) async {
    await db.execute('''
      CREATE TABLE captured_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        key TEXT NOT NULL UNIQUE,
        package TEXT NOT NULL,
        posted_at INTEGER NOT NULL,
        direction TEXT NOT NULL,
        amount INTEGER NOT NULL,
        title TEXT NOT NULL DEFAULT '',
        body TEXT NOT NULL DEFAULT '',
        counterparty TEXT,
        upi_ref TEXT,
        account_hint TEXT,
        status TEXT NOT NULL DEFAULT 'pending',
        txn_id INTEGER REFERENCES transactions(id) ON DELETE SET NULL,
        duplicate_of INTEGER
      )''');
    await db.execute('CREATE INDEX idx_captured_status ON captured_payments(status, posted_at)');
  }

  /// v3: this phone's own settings, such as app lock and the backup
  /// folder. Backups leave this table out, since it describes the phone.
  static Future<void> _createV3(Database db) async {
    await db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
  }

  static Future<void> _migrate(Database db, int from, int to) async {
    if (from < 2) await _createV2(db);
    if (from < 3) await _createV3(db);
  }

  Future<void> close() => db.close();
}
