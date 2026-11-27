import 'dart:convert';

import 'package:finance_tracker/data/db/app_database.dart';
import 'package:finance_tracker/data/finance_repository.dart';
import 'package:finance_tracker/data/models/txn.dart';
import 'package:finance_tracker/services/backup/auto_backup_service.dart';
import 'package:finance_tracker/services/backup/drive_auth.dart';
import 'package:finance_tracker/services/backup/drive_backup_service.dart';
import 'package:finance_tracker/services/backup/drive_client.dart';
import 'package:finance_tracker/services/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Google's side of sign-in, scripted.
class FakeAuth implements DriveAuth {
  /// What an interactive ask returns. Null is the user backing out.
  String? interactiveToken = 'token-1';

  /// What a silent ask returns. Null means Google needs the user again.
  String? silentToken = 'token-1';
  Object? error;
  final forgotten = <String>[];
  final asked = <bool>[];

  @override
  Future<String?> token({required bool interactive}) async {
    asked.add(interactive);
    if (error != null) throw error!;
    return interactive ? interactiveToken : silentToken;
  }

  @override
  Future<void> forget(String token) async => forgotten.add(token);
}

/// A tiny Drive that keeps files in memory and checks the token.
class FakeDrive {
  final files = <String, ({String name, String text, DateTime created})>{};
  final validTokens = {'token-1'};
  final revoked = <String>[];
  var clock = DateTime.utc(2026, 11, 23);
  var nextId = 0;
  int? failStatus;
  String failBody = '';
  late final http.Client client = MockClient(_handle);

  Future<http.Response> _handle(http.Request r) async {
    if (r.url.host == 'oauth2.googleapis.com') {
      revoked.add(r.bodyFields['token']!);
      return http.Response('', 200);
    }
    final token = r.headers['Authorization']?.replaceFirst('Bearer ', '');
    if (!validTokens.contains(token)) return http.Response('{"error":{"code":401}}', 401);
    if (failStatus != null) return http.Response(failBody, failStatus!);
    final path = r.url.path;
    if (r.method == 'POST' && path == '/upload/drive/v3/files') {
      expect(r.url.queryParameters['uploadType'], 'multipart');
      final body = r.body;
      final parts = body.split('\r\n\r\n');
      final meta = jsonDecode(parts[1].split('\r\n').first) as Map<String, Object?>;
      expect(meta['parents'], ['appDataFolder']);
      final text = parts[2].substring(0, parts[2].lastIndexOf('\r\n--'));
      final id = 'f${nextId++}';
      clock = clock.add(const Duration(minutes: 1));
      files[id] = (name: meta['name']! as String, text: text, created: clock);
      return http.Response(jsonEncode(_json(id)), 200);
    }
    if (r.method == 'GET' && path == '/drive/v3/files') {
      expect(r.url.queryParameters['spaces'], 'appDataFolder');
      return http.Response(jsonEncode({'files': files.keys.map(_json).toList()}), 200);
    }
    if (r.method == 'GET' && path.startsWith('/drive/v3/files/')) {
      final f = files[path.split('/').last];
      return f == null ? http.Response('', 404) : http.Response.bytes(utf8.encode(f.text), 200);
    }
    if (r.method == 'DELETE' && path.startsWith('/drive/v3/files/')) {
      files.remove(path.split('/').last);
      return http.Response('', 204);
    }
    if (path == '/drive/v3/about') {
      return http.Response(
        jsonEncode({
          'user': {'emailAddress': 'me@example.com'},
        }),
        200,
      );
    }
    return http.Response('not found', 404);
  }

  Map<String, Object?> _json(String id) => {
    'id': id,
    'name': files[id]!.name,
    'createdTime': files[id]!.created.toIso8601String(),
    'size': '${files[id]!.text.length}',
  };
}

void main() {
  sqfliteFfiInit();
  late AppDatabase database;
  late FinanceRepository repo;
  late FakeAuth auth;
  late FakeDrive drive;
  late DriveBackupService service;
  final monday = DateTime(2026, 11, 23, 9, 30);

  setUp(() async {
    database = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    repo = FinanceRepository(database);
    auth = FakeAuth();
    drive = FakeDrive();
    service = DriveBackupService(repo, BackupService(repo.database), DriveClient(drive.client), auth);
  });
  tearDown(() => database.close());

  test('is off until connected, and connecting backs up at once', () async {
    expect((await service.status()).on, isFalse);
    expect(await service.runIfDue(monday), isFalse);
    expect(auth.asked, isEmpty, reason: 'nothing asks Google while it is off');

    expect(await service.connect(monday), isTrue);
    final s = await service.status();
    expect(s.on, isTrue);
    expect(s.account, 'me@example.com');
    expect(s.lastAt, monday);
    expect(s.error, isNull);
    expect(drive.files.values.single.name, 'finance-tracker-auto-2026-11-23_0930.json');
    expect(auth.asked, [true]);
  });

  test('backing out of Google\'s screen leaves it off', () async {
    auth.interactiveToken = null;
    expect(await service.connect(monday), isFalse);
    expect((await service.status()).on, isFalse);
    expect(drive.files, isEmpty);
  });

  test('a setup problem is reported in words and leaves it off', () async {
    auth.error = const DriveAuthException('Google sign-in isn\'t set up for this copy of the app yet.');
    await expectLater(
      service.connect(monday),
      throwsA(isA<AutoBackupException>().having((e) => e.message, 'message', contains('isn\'t set up'))),
    );
    expect((await service.status()).on, isFalse);
  });

  test('backs up again once a week has passed, silently, and keeps the newest four', () async {
    await service.connect(monday);
    expect(await service.runIfDue(monday.add(const Duration(days: 6))), isFalse);
    for (var week = 1; week <= 5; week++) {
      expect(await service.runIfDue(monday.add(Duration(days: 7 * week))), isTrue);
    }
    expect(auth.asked.skip(1), everyElement(isFalse), reason: 'the weekly run never shows Google\'s screen');
    expect(drive.files, hasLength(DriveBackupService.keep));
    final names = drive.files.values.map((f) => f.name).toList()..sort();
    expect(names.first, 'finance-tracker-auto-2026-12-07_0930.json');
    expect(names.last, 'finance-tracker-auto-2026-12-28_0930.json');
  });

  test('with the weekly run off, Drive only gets a copy on tap, and each holds everything', () async {
    await service.connect(monday);
    await service.setWeekly(false);
    expect((await service.status()).weekly, isFalse);
    expect((await service.status()).nextAt, isNull);
    final later = monday.add(const Duration(days: 30));
    expect(await service.runIfDue(later), isFalse);
    expect(drive.files, hasLength(1));

    final account = (await repo.accounts()).first;
    final category = (await repo.categories()).first;
    await repo.saveTxn(
      Txn(
        type: TxnType.expense,
        amount: 9900,
        date: later,
        accountId: account.id!,
        categoryId: category.id,
        note: 'Books',
      ),
    );
    await service.backUp(later);
    final newest = (await service.backups()).first;
    final tables = (jsonDecode(await service.read(newest)) as Map<String, Object?>)['tables']! as Map<String, Object?>;
    expect((tables['transactions']! as List).map((t) => (t as Map)['note']), contains('Books'));
    expect((tables['accounts']! as List), isNotEmpty, reason: 'a full copy, not only what changed');

    await service.setWeekly(true);
    expect(await service.runIfDue(later.add(const Duration(days: 7))), isTrue);
  });

  test('turning the weekly run off clears a waiting sign-in nag', () async {
    await service.connect(monday);
    auth.silentToken = null;
    await expectLater(service.runIfDue(monday.add(const Duration(days: 7))), throwsA(isA<AutoBackupException>()));
    await service.setWeekly(false);
    expect((await service.status()).error, isNull);
  });

  test('a refused token is dropped and tried once more with a fresh one', () async {
    await service.connect(monday);
    drive.validTokens
      ..clear()
      ..add('token-2');
    auth.silentToken = 'token-2';
    expect(await service.runIfDue(monday.add(const Duration(days: 7))), isTrue);
    expect(auth.forgotten, isEmpty, reason: 'token-2 worked straight away');

    drive.validTokens
      ..clear()
      ..add('token-3');
    final tokens = ['token-2', 'token-3'];
    auth.silentToken = null;
    final retrying = _SequenceAuth(tokens);
    service = DriveBackupService(repo, BackupService(repo.database), DriveClient(drive.client), retrying);
    expect(await service.runIfDue(monday.add(const Duration(days: 14))), isTrue);
    expect(retrying.forgotten, ['token-2']);
    expect((await service.status()).error, isNull);
  });

  test('when Google wants the user again, the weekly run says so and tries on the next open', () async {
    await service.connect(monday);
    auth.silentToken = null;
    final due = monday.add(const Duration(days: 7));
    await expectLater(service.runIfDue(due), throwsA(isA<AutoBackupException>()));
    expect((await service.status()).error, DriveBackupService.signInAgain);
    await expectLater(
      service.runIfDue(due.add(const Duration(hours: 1))),
      throwsA(isA<AutoBackupException>()),
      reason: 'it asks again on every open until it works',
    );

    // Back up now may show Google's screen, and clears the error.
    await service.backUp(due.add(const Duration(hours: 2)));
    expect((await service.status()).error, isNull);
    expect(await service.runIfDue(due.add(const Duration(hours: 3))), isFalse);
  });

  test('a full Drive and no connection get their own words', () async {
    await service.connect(monday);
    drive
      ..failStatus = 403
      ..failBody = '{"error":{"errors":[{"reason":"storageQuotaExceeded"}]}}';
    await expectLater(
      service.backUp(monday.add(const Duration(days: 7))),
      throwsA(isA<AutoBackupException>().having((e) => e.message, 'message', contains('full'))),
    );
    final offline = DriveBackupService(
      repo,
      BackupService(repo.database),
      DriveClient(MockClient((_) async => throw http.ClientException('no network'))),
      auth,
    );
    await expectLater(
      offline.backUp(monday.add(const Duration(days: 8))),
      throwsA(isA<AutoBackupException>().having((e) => e.message, 'message', contains('connection'))),
    );
  });

  test('a backup read from Drive restores the entries', () async {
    final account = (await repo.accounts()).first;
    final category = (await repo.categories()).first;
    await repo.saveTxn(
      Txn(
        type: TxnType.expense,
        amount: 25000,
        date: monday,
        accountId: account.id!,
        categoryId: category.id,
        note: 'Lunch',
      ),
    );
    await service.connect(monday);
    final backups = await service.backups();
    expect(backups, hasLength(1));

    final backup = BackupService(repo.database);
    await backup.restore(await _emptyBackup(backup));
    expect(await repo.allTxns(), isEmpty);

    await backup.restore(await service.read(backups.single));
    expect((await repo.allTxns()).single.note, 'Lunch');
  });

  test('turning off takes back the access and leaves the backups in Drive', () async {
    await service.connect(monday);
    await service.turnOff();
    expect(drive.revoked, ['token-1']);
    expect(auth.forgotten, ['token-1']);
    final s = await service.status();
    expect(s.on, isFalse);
    expect(s.lastAt, isNull);
    expect(drive.files, hasLength(1));
    expect(await service.runIfDue(monday.add(const Duration(days: 30))), isFalse);
  });

  test('the client asks Drive for every page of the list, newest first', () async {
    var call = 0;
    final client = DriveClient(
      MockClient((r) async {
        call++;
        if (call == 1) {
          expect(r.url.queryParameters.containsKey('pageToken'), isFalse);
          return http.Response(
            jsonEncode({
              'nextPageToken': 'p2',
              'files': [
                {'id': 'a', 'name': 'old', 'createdTime': '2026-01-01T00:00:00Z'},
              ],
            }),
            200,
          );
        }
        expect(r.url.queryParameters['pageToken'], 'p2');
        return http.Response(
          jsonEncode({
            'files': [
              {'id': 'b', 'name': 'new', 'createdTime': '2026-02-01T00:00:00Z', 'size': '2048'},
            ],
          }),
          200,
        );
      }),
    );
    final files = await client.list('t');
    expect(files.map((f) => f.id), ['b', 'a']);
    expect(files.first.size, 2048);
  });
}

/// Hands out tokens in order, then none.
class _SequenceAuth implements DriveAuth {
  _SequenceAuth(this._tokens);

  final List<String> _tokens;
  final forgotten = <String>[];

  @override
  Future<String?> token({required bool interactive}) async => _tokens.isEmpty ? null : _tokens.removeAt(0);

  @override
  Future<void> forget(String token) async => forgotten.add(token);
}

/// A backup of a database with no entries, made by deleting them first.
Future<String> _emptyBackup(BackupService backup) async {
  final json = jsonDecode(await backup.export()) as Map<String, Object?>;
  (json['tables']! as Map<String, Object?>)['transactions'] = <Object?>[];
  return jsonEncode(json);
}
