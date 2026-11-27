import 'dart:convert';

import 'package:finance_tracker/data/db/app_database.dart';
import 'package:finance_tracker/data/finance_repository.dart';
import 'package:finance_tracker/services/backup/auto_backup_service.dart';
import 'package:finance_tracker/services/backup/backup_folder_channel.dart';
import 'package:finance_tracker/services/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A folder in memory.
class FakeFolder extends BackupFolderChannel {
  PickedFolder? toPick = const PickedFolder('content://tree/download', 'Download');
  bool access = true;
  bool failWrite = false;
  final files = <String, String>{};
  final released = <String>[];
  int? keptAsked;

  @override
  Future<PickedFolder?> pick() async => toPick;

  @override
  Future<bool> hasAccess(String uri) async => access;

  @override
  Future<void> release(String uri) async => released.add(uri);

  @override
  Future<String> write(String uri, String name, String text, {required int keep}) async {
    if (failWrite) throw Exception('disk full');
    keptAsked = keep;
    files[name] = text;
    return name;
  }
}

void main() {
  sqfliteFfiInit();
  late AppDatabase database;
  late FinanceRepository repo;
  late FakeFolder folder;
  late AutoBackupService auto;
  final monday = DateTime(2026, 11, 23, 9, 30);

  setUp(() async {
    database = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    repo = FinanceRepository(database);
    folder = FakeFolder();
    auto = AutoBackupService(repo, BackupService(repo.database), folder);
  });
  tearDown(() => database.close());

  test('is off until a folder is chosen, and choosing one backs up at once', () async {
    expect((await auto.status()).on, isFalse);
    expect(await auto.runIfDue(monday), isFalse);
    expect(folder.files, isEmpty);

    expect(await auto.chooseFolder(monday), isTrue);
    final s = await auto.status();
    expect(s.on, isTrue);
    expect(s.folderName, 'Download');
    expect(s.lastAt, monday);
    expect(s.nextAt, monday.add(const Duration(days: 7)));
    expect(folder.files.keys, ['finance-tracker-auto-2026-11-23_0930.json']);
    expect(folder.keptAsked, AutoBackupService.keep);
    expect(jsonDecode(folder.files.values.single), containsPair('tables', isA<Map<String, Object?>>()));
  });

  test('a cancelled picker leaves it off', () async {
    folder.toPick = null;
    expect(await auto.chooseFolder(monday), isFalse);
    expect((await auto.status()).on, isFalse);
  });

  test('backs up again only once a week has passed', () async {
    await auto.chooseFolder(monday);
    expect(await auto.runIfDue(monday.add(const Duration(days: 6, hours: 23))), isFalse);
    expect(await auto.runIfDue(monday.add(const Duration(days: 7))), isTrue);
    expect(folder.files, hasLength(2));
  });

  test('a lost folder is reported, and retried on the next open', () async {
    await auto.chooseFolder(monday);
    folder.access = false;
    final later = monday.add(const Duration(days: 8));
    await expectLater(auto.runIfDue(later), throwsA(isA<AutoBackupException>()));
    final s = await auto.status();
    expect(s.error, contains('Download can\'t be reached'));
    expect(s.lastAt, monday, reason: 'the last good backup is still shown');

    folder.access = true;
    expect(await auto.runIfDue(later.add(const Duration(hours: 1))), isTrue);
    expect((await auto.status()).error, isNull);
  });

  test('a failed write keeps a message and stays due', () async {
    await auto.chooseFolder(monday);
    folder.failWrite = true;
    final later = monday.add(const Duration(days: 7));
    await expectLater(auto.backUp(later), throwsA(isA<AutoBackupException>()));
    expect((await auto.status()).error, isNotNull);
    folder.failWrite = false;
    expect(await auto.runIfDue(later.add(const Duration(minutes: 5))), isTrue);
  });

  test('turning off forgets the folder and gives up its permission', () async {
    await auto.chooseFolder(monday);
    await auto.turnOff();
    final s = await auto.status();
    expect(s.on, isFalse);
    expect(s.lastAt, isNull);
    expect(folder.released, ['content://tree/download']);
  });

  test('changing folder releases the old one', () async {
    await auto.chooseFolder(monday);
    folder.toPick = const PickedFolder('content://tree/backups', 'Backups');
    await auto.chooseFolder(monday.add(const Duration(minutes: 1)));
    expect(folder.released, ['content://tree/download']);
    expect((await auto.status()).folderName, 'Backups');
  });

  test('the folder setting never goes into the backup file itself', () async {
    await auto.chooseFolder(monday);
    expect(folder.files.values.single, isNot(contains('content://tree')));
  });
}
