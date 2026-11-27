import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../data/db/app_database.dart';

/// Thrown when a file isn't a backup this version of the app can restore.
class BackupException implements Exception {
  const BackupException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// What a backup file holds, read before anything is replaced.
class BackupInfo {
  const BackupInfo({required this.createdAt, required this.entryCount, required this.tables});

  final DateTime createdAt;

  /// Number of transactions in the backup.
  final int entryCount;
  final Map<String, List<Map<String, Object?>>> tables;
}

/// Saves every table to one JSON file and puts it back, so entries survive
/// a reinstall or a new phone. Receipt screenshots are not included.
class BackupService {
  BackupService(this._db);

  final Database _db;

  static const _format = 'finance_tracker_backup';

  /// Every row of every app table, as JSON.
  Future<String> export({DateTime? now}) async {
    final tables = <String, Object?>{};
    for (final name in await _tableNames(_db)) {
      tables[name] = await _db.query(name);
    }
    return jsonEncode({
      'format': _format,
      'schema': AppDatabase.schemaVersion,
      'createdAt': (now ?? DateTime.now()).toIso8601String(),
      'tables': tables,
    });
  }

  /// Checks a backup without changing anything.
  BackupInfo inspect(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      throw const BackupException('This isn\'t a Finance Tracker backup.');
    }
    if (json is! Map<String, Object?> || json['format'] != _format || json['tables'] is! Map) {
      throw const BackupException('This isn\'t a Finance Tracker backup.');
    }
    final schema = json['schema'];
    if (schema is! int || schema > AppDatabase.schemaVersion) {
      throw const BackupException('This backup is from a newer version of the app. Update the app, then restore.');
    }
    final createdAt = DateTime.tryParse('${json['createdAt']}');
    final tables = <String, List<Map<String, Object?>>>{};
    for (final MapEntry(:key, :value) in (json['tables'] as Map).entries) {
      if (key is! String || value is! List || value.any((r) => r is! Map)) {
        throw const BackupException('This backup is damaged and can\'t be restored.');
      }
      tables[key] = [for (final r in value) Map<String, Object?>.from(r as Map)];
    }
    return BackupInfo(
      createdAt: createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      entryCount: tables['transactions']?.length ?? 0,
      tables: tables,
    );
  }

  /// Replaces everything in the app with the backup, in one transaction, so
  /// a failure leaves the current data as it was.
  Future<void> restore(String text) async {
    final info = inspect(text);
    await _db.transaction((txn) async {
      await txn.execute('PRAGMA defer_foreign_keys = ON');
      final names = await _tableNames(txn);
      for (final name in names) {
        await txn.delete(name);
      }
      for (final name in names) {
        final rows = info.tables[name];
        if (rows == null) continue;
        final columns = await _columns(txn, name);
        for (final row in rows) {
          await txn.insert(name, {
            for (final MapEntry(:key, :value) in row.entries)
              if (columns.contains(key)) key: value,
          });
        }
      }
    });
  }

  /// Tables that describe this phone rather than your money, such as the
  /// app lock and the backup folder. They are neither saved nor replaced.
  static const _phoneOnly = {'settings'};

  static Future<List<String>> _tableNames(DatabaseExecutor db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata' "
      "AND name NOT IN (${_phoneOnly.map((t) => "'$t'").join(', ')}) ORDER BY name",
    );
    return [for (final r in rows) r['name']! as String];
  }

  static Future<Set<String>> _columns(DatabaseExecutor db, String table) async {
    final rows = await db.rawQuery('PRAGMA table_info("$table")');
    return {for (final r in rows) r['name']! as String};
  }
}
