import 'dart:developer';

import 'package:local_auth/local_auth.dart';

/// What happened when the phone was asked to unlock the app.
enum UnlockResult {
  /// Fingerprint, face, PIN, pattern or password was accepted.
  unlocked,

  /// The prompt was closed, or the app was left while it showed.
  cancelled,

  /// The phone has no screen lock, so there is nothing to check against.
  noScreenLock,

  /// Too many wrong tries; the phone asks to wait before the next one.
  lockedOut,

  /// Anything else the phone reported.
  failed,
}

/// Asks the phone's own screen lock to unlock the app. Fingerprint or face
/// is offered first where set up, and the phone's PIN, pattern or password
/// always works, so a wet finger never locks anyone out.
class AppLockService {
  AppLockService([LocalAuthentication? auth]) : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  /// True while the unlock prompt is showing. The phone pauses the app
  /// behind its PIN screen, and that pause must not count as leaving.
  bool get inProgress => _inProgress;
  bool _inProgress = false;

  /// Whether the phone has a screen lock the app can use.
  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (e, st) {
      log('Could not check the screen lock', error: e, stackTrace: st);
      return false;
    }
  }

  /// Shows the phone's unlock prompt with [reason] under it.
  Future<UnlockResult> unlock(String reason) async {
    if (_inProgress) return UnlockResult.cancelled;
    _inProgress = true;
    try {
      final ok = await _auth.authenticate(localizedReason: reason);
      return ok ? UnlockResult.unlocked : UnlockResult.cancelled;
    } on LocalAuthException catch (e) {
      return switch (e.code) {
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.timeout ||
        LocalAuthExceptionCode.authInProgress => UnlockResult.cancelled,
        LocalAuthExceptionCode.noCredentialsSet => UnlockResult.noScreenLock,
        LocalAuthExceptionCode.temporaryLockout || LocalAuthExceptionCode.biometricLockout => UnlockResult.lockedOut,
        _ => _failed(e),
      };
    } catch (e, st) {
      log('Unlock failed', error: e, stackTrace: st);
      return UnlockResult.failed;
    } finally {
      _inProgress = false;
    }
  }

  UnlockResult _failed(LocalAuthException e) {
    log('Unlock failed: ${e.code.name} ${e.description ?? ''}');
    return UnlockResult.failed;
  }
}
