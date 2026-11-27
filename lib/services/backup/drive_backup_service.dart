import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../data/finance_repository.dart';
import '../backup_service.dart';
import 'auto_backup_service.dart';
import 'drive_auth.dart';
import 'drive_client.dart';

/// Whether backups also go to Google Drive, and how the last one went.
class DriveBackupStatus {
  const DriveBackupStatus({this.on = false, this.weekly = true, this.account, this.lastAt, this.error});

  final bool on;

  /// Whether a copy goes up by itself once a week. When false, Drive only
  /// gets one when the user taps Back up now.
  final bool weekly;

  /// The Google account's email, when Drive said which it is.
  final String? account;
  final DateTime? lastAt;

  /// Why the last try failed, in words for the user. Null after a success.
  final String? error;

  DateTime? get nextAt => !on || !weekly ? null : lastAt?.add(AutoBackupService.every);
}

/// Copies a backup into the app's hidden folder in the user's Google
/// Drive, on the same weekly schedule as the folder backup or only when
/// asked, and reads those copies back to restore. Every copy holds all the
/// app's data, so the newest one is always complete. Only the app can see that folder, and the
/// app can see nothing else in Drive.
class DriveBackupService {
  DriveBackupService(this._repo, this._backup, this._drive, this._auth);

  final FinanceRepository _repo;
  final BackupService _backup;
  final DriveClient _drive;
  final DriveAuth _auth;

  static const keep = AutoBackupService.keep;

  static const _onKey = 'drive_backup_on';
  static const _accountKey = 'drive_backup_account';
  static const _weeklyKey = 'drive_backup_weekly';
  static const _lastKey = 'drive_backup_last';
  static const _errorKey = 'drive_backup_error';

  static const signInAgain = 'Google Drive needs you to sign in again. Tap Back up now.';

  Future<DriveBackupStatus> status() async {
    final last = await _repo.setting(_lastKey);
    return DriveBackupStatus(
      on: await _repo.setting(_onKey) != null,
      weekly: await _repo.setting(_weeklyKey) != 'off',
      account: await _repo.setting(_accountKey),
      lastAt: last == null ? null : DateTime.tryParse(last),
      error: await _repo.setting(_errorKey),
    );
  }

  /// Asks Google for access to the app's Drive folder and backs up at once.
  /// Returns false when the user backed out. Throws [AutoBackupException]
  /// when access was refused or the first backup failed.
  Future<bool> connect(DateTime now) async {
    final token = await _guard(() => _auth.token(interactive: true));
    if (token == null) return false;
    await _repo.setSetting(_onKey, 'on');
    await _repo.setSetting(_accountKey, await _drive.accountEmail(token));
    await _record(() => _upload(token, now), now);
    return true;
  }

  /// Stops Drive backups and takes back the app's access. The backups
  /// already in Drive stay there, so a later restore can still find them.
  Future<void> turnOff() async {
    try {
      final token = await _auth.token(interactive: false);
      if (token != null) {
        await _drive.revoke(token);
        await _auth.forget(token);
      }
    } catch (e, st) {
      log('Could not take back Drive access', error: e, stackTrace: st);
    }
    for (final key in [_onKey, _weeklyKey, _accountKey, _lastKey, _errorKey]) {
      await _repo.setSetting(key, null);
    }
  }

  /// Whether a copy goes up by itself each week, or only when asked.
  Future<void> setWeekly(bool weekly) async {
    await _repo.setSetting(_weeklyKey, weekly ? null : 'off');
    // A failed weekly try has nothing left to retry once it's off.
    if (!weekly && await _repo.setting(_errorKey) == DriveBackupService.signInAgain) {
      await _repo.setSetting(_errorKey, null);
    }
  }

  /// Backs up when it's on and a week has passed, without showing anything.
  /// Returns false when it wasn't due; throws [AutoBackupException] when it
  /// was due and failed.
  Future<bool> runIfDue(DateTime now) async {
    final s = await status();
    if (!s.on || !s.weekly) return false;
    if (s.lastAt != null && now.difference(s.lastAt!) < AutoBackupService.every && s.error == null) return false;
    await backUp(now, interactive: false);
    return true;
  }

  /// Backs up now. With [interactive], Google may ask the user to sign in.
  Future<void> backUp(DateTime now, {bool interactive = true}) =>
      _record(() => _withToken(interactive, (token) => _upload(token, now)), now);

  /// The backups in Drive, newest first. May ask the user to sign in, as
  /// on a new phone.
  Future<List<DriveFile>> backups() => _guard(() => _withToken(true, _drive.list));

  /// The text of one backup, ready for [BackupService.restore].
  Future<String> read(DriveFile file) => _guard(() => _withToken(true, (t) => _drive.download(t, file.id)));

  Future<void> _upload(String token, DateTime now) async {
    await _drive.upload(token, AutoBackupService.fileName(now), await _backup.export(now: now));
    final files = await _drive.list(token);
    for (final old in files.skip(keep)) {
      await _drive.delete(token, old.id);
    }
  }

  /// Runs [action] with a token, and once more with a fresh one if Drive
  /// refused the first.
  Future<T> _withToken<T>(bool interactive, Future<T> Function(String token) action) async {
    var token = await _auth.token(interactive: interactive);
    if (token == null) throw interactive ? const DriveSignInCancelled() : const AutoBackupException(signInAgain);
    try {
      return await action(token);
    } on DriveAuthExpired {
      await _auth.forget(token);
      token = await _auth.token(interactive: interactive);
      if (token == null) throw const AutoBackupException(signInAgain);
      try {
        return await action(token);
      } on DriveAuthExpired {
        throw const AutoBackupException(signInAgain);
      }
    }
  }

  Future<void> _record(Future<void> Function() action, DateTime now) async {
    try {
      await _guard(action);
      await _repo.setSetting(_lastKey, now.toIso8601String());
      await _repo.setSetting(_errorKey, null);
    } on AutoBackupException catch (e) {
      await _repo.setSetting(_errorKey, e.message);
      rethrow;
    }
  }

  /// Turns every failure into an [AutoBackupException] with words for the
  /// user.
  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AutoBackupException {
      rethrow;
    } on DriveSignInCancelled {
      rethrow;
    } on DriveAuthException catch (e) {
      throw AutoBackupException(e.message);
    } on DriveAuthExpired {
      throw const AutoBackupException(signInAgain);
    } on SocketException {
      throw const AutoBackupException('Google Drive couldn\'t be reached. Check your connection.');
    } on http.ClientException {
      throw const AutoBackupException('Google Drive couldn\'t be reached. Check your connection.');
    } on TimeoutException {
      throw const AutoBackupException('Google Drive couldn\'t be reached. Check your connection.');
    } on DriveRequestException catch (e, st) {
      log('Drive request failed', error: e, stackTrace: st);
      if (e.status == 403 && e.body.contains('accessNotConfigured')) {
        throw const AutoBackupException(
          'The Google Drive API is turned off in your Google Cloud project. The README says how to turn it on.',
        );
      }
      if (e.status == 403 && e.body.contains('storageQuotaExceeded')) {
        throw const AutoBackupException('Your Google Drive is full, so the backup couldn\'t be saved.');
      }
      throw const AutoBackupException('Google Drive didn\'t take the backup. Try again later.');
    } catch (e, st) {
      log('Drive backup failed', error: e, stackTrace: st);
      throw const AutoBackupException('Google Drive didn\'t take the backup. Try again later.');
    }
  }
}
