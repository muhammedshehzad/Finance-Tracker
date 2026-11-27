import 'dart:developer';

import 'package:intl/intl.dart';

import '../../data/finance_repository.dart';
import '../backup_service.dart';
import 'backup_folder_channel.dart';

/// Where automatic backups go and how the last one went.
class AutoBackupStatus {
  const AutoBackupStatus({this.folderUri, this.folderName, this.lastAt, this.lastFile, this.error});

  final String? folderUri;
  final String? folderName;
  final DateTime? lastAt;
  final String? lastFile;

  /// Why the last try failed, in words for the user. Null after a success.
  final String? error;

  /// Whether automatic backup is on.
  bool get on => folderUri != null;

  /// When the next backup is due, once the app is opened.
  DateTime? get nextAt => !on ? null : lastAt?.add(AutoBackupService.every);
}

/// Saves a backup file into a folder the user chose, once a week, when the
/// app is opened. The data only changes while the app is open, so a week
/// without opening it loses nothing. The newest [keep] files are kept.
class AutoBackupService {
  AutoBackupService(this._repo, this._backup, this._folder);

  final FinanceRepository _repo;
  final BackupService _backup;
  final BackupFolderChannel _folder;

  static const every = Duration(days: 7);
  static const keep = 4;

  static const _folderKey = 'auto_backup_folder';
  static const _folderNameKey = 'auto_backup_folder_name';
  static const _lastKey = 'auto_backup_last';
  static const _fileKey = 'auto_backup_file';
  static const _errorKey = 'auto_backup_error';

  /// The file name for a backup made at [now]. Sorts by date, and the
  /// Android side only ever deletes files named this way.
  static String fileName(DateTime now) => 'finance-tracker-auto-${DateFormat('yyyy-MM-dd_HHmm').format(now)}.json';

  Future<AutoBackupStatus> status() async {
    final last = await _repo.setting(_lastKey);
    return AutoBackupStatus(
      folderUri: await _repo.setting(_folderKey),
      folderName: await _repo.setting(_folderNameKey),
      lastAt: last == null ? null : DateTime.tryParse(last),
      lastFile: await _repo.setting(_fileKey),
      error: await _repo.setting(_errorKey),
    );
  }

  /// Asks for a folder, then backs up into it straight away. Returns false
  /// when no folder was chosen.
  Future<bool> chooseFolder(DateTime now) async {
    final picked = await _folder.pick();
    if (picked == null) return false;
    final old = await _repo.setting(_folderKey);
    if (old != null && old != picked.uri) await _releaseQuietly(old);
    await _repo.setSetting(_folderKey, picked.uri);
    await _repo.setSetting(_folderNameKey, picked.name);
    await backUp(now);
    return true;
  }

  /// Stops automatic backups. Files already saved stay in the folder.
  Future<void> turnOff() async {
    final uri = await _repo.setting(_folderKey);
    if (uri != null) await _releaseQuietly(uri);
    for (final key in [_folderKey, _folderNameKey, _lastKey, _fileKey, _errorKey]) {
      await _repo.setSetting(key, null);
    }
  }

  /// Backs up when it's on and a week has passed. Returns false when it
  /// wasn't due; throws [AutoBackupException] when it was due and failed.
  Future<bool> runIfDue(DateTime now) async {
    final s = await status();
    if (!s.on) return false;
    if (s.lastAt != null && now.difference(s.lastAt!) < every && s.error == null) return false;
    await backUp(now);
    return true;
  }

  /// Backs up now. Records the result either way.
  Future<void> backUp(DateTime now) async {
    final uri = await _repo.setting(_folderKey);
    if (uri == null) throw const AutoBackupException('Choose a folder first.');
    final folderName = await _repo.setting(_folderNameKey) ?? 'the folder';
    try {
      if (!await _folder.hasAccess(uri)) {
        throw AutoBackupException('$folderName can\'t be reached any more. Choose the folder again.');
      }
      final written = await _folder.write(uri, fileName(now), await _backup.export(now: now), keep: keep);
      await _repo.setSetting(_lastKey, now.toIso8601String());
      await _repo.setSetting(_fileKey, written);
      await _repo.setSetting(_errorKey, null);
    } on AutoBackupException catch (e) {
      await _repo.setSetting(_errorKey, e.message);
      rethrow;
    } catch (e, st) {
      log('Automatic backup failed', error: e, stackTrace: st);
      const message = 'The backup couldn\'t be saved in the folder. Try again, or choose another folder.';
      await _repo.setSetting(_errorKey, message);
      throw const AutoBackupException(message);
    }
  }

  Future<void> _releaseQuietly(String uri) async {
    try {
      await _folder.release(uri);
    } catch (e, st) {
      log('Could not release the backup folder', error: e, stackTrace: st);
    }
  }
}

/// A backup that couldn't be made, with a message for the user.
class AutoBackupException implements Exception {
  const AutoBackupException(this.message);

  final String message;

  @override
  String toString() => message;
}
