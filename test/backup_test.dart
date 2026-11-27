import 'dart:convert';

import 'package:finance_tracker/data/db/app_database.dart';
import 'package:finance_tracker/data/finance_repository.dart';
import 'package:finance_tracker/data/models/account.dart';
import 'package:finance_tracker/data/models/category.dart';
import 'package:finance_tracker/data/models/txn.dart';
import 'package:finance_tracker/services/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late AppDatabase database;
  late FinanceRepository repo;
  late BackupService backup;

  setUp(() async {
    database = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    repo = FinanceRepository(database);
    backup = BackupService(repo.database);
  });
  tearDown(() => database.close());

  Future<int> addLunch(int paise) async {
    final bank = (await repo.accounts()).firstWhere((a) => a.kind == AccountKind.bank).id!;
    final food = (await repo.categories(kind: CategoryKind.expense)).firstWhere((c) => c.name == 'Food').id!;
    return repo.saveTxn(
      Txn(type: TxnType.expense, amount: paise, date: DateTime(2026, 11, 20, 13), accountId: bank, categoryId: food),
    );
  }

  test('restore brings back exactly what was backed up', () async {
    await addLunch(9000);
    final saved = await backup.export(now: DateTime(2026, 11, 26, 9));
    final accountsBefore = (await repo.accounts(includeArchived: true)).length;

    await addLunch(3000);
    await repo.saveAccount(const Account(name: 'Wallet 2', kind: AccountKind.cash));
    await backup.restore(saved);

    final txns = await repo.allTxns();
    expect(txns.map((t) => t.amount), [9000]);
    expect((await repo.accounts(includeArchived: true)).length, accountsBefore);
  });

  test('phone settings such as app lock stay out of backups and survive a restore', () async {
    await repo.setSetting('app_lock', 'on');
    final saved = await backup.export(now: DateTime(2026, 11, 26, 9));
    expect((jsonDecode(saved) as Map)['tables'], isNot(contains('settings')));

    await repo.setSetting('app_lock', null);
    await backup.restore(saved);
    expect(await repo.setting('app_lock'), isNull);

    await repo.setSetting('app_lock', 'on');
    await backup.restore(saved);
    expect(await repo.setting('app_lock'), 'on');
  });

  test('inspect reports the date and number of entries', () async {
    await addLunch(9000);
    await addLunch(2600);
    final info = backup.inspect(await backup.export(now: DateTime(2026, 11, 26, 9)));
    expect(info.createdAt, DateTime(2026, 11, 26, 9));
    expect(info.entryCount, 2);
  });

  test('rejects files that are not backups', () {
    expect(() => backup.inspect('hello'), throwsA(isA<BackupException>()));
    expect(() => backup.inspect('{"tables": {}}'), throwsA(isA<BackupException>()));
  });

  test('rejects a backup from a newer version and leaves data alone', () async {
    await addLunch(9000);
    final newer = jsonDecode(await backup.export()) as Map<String, Object?>;
    newer['schema'] = AppDatabase.schemaVersion + 1;
    await expectLater(backup.restore(jsonEncode(newer)), throwsA(isA<BackupException>()));
    expect((await repo.allTxns()).length, 1);
  });
}
