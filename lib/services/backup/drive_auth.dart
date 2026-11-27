import 'dart:developer';

import 'package:google_sign_in/google_sign_in.dart';

import 'drive_client.dart';

/// Why Google wouldn't give access, in words for the user.
class DriveAuthException implements Exception {
  const DriveAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The user backed out of Google's sign-in. Nothing to report.
class DriveSignInCancelled implements Exception {
  const DriveSignInCancelled();
}

/// Gets access tokens for the app's hidden Drive folder.
abstract class DriveAuth {
  /// A token for [DriveClient.scope]. With [interactive], Google may show
  /// its account picker and consent screen; null means the user backed out.
  /// Without it nothing is shown, and null means Google needs the user to
  /// sign in again.
  Future<String?> token({required bool interactive});

  /// Drops a token Drive refused, so the next one is fresh.
  Future<void> forget(String token);
}

/// [DriveAuth] through Google Play services, by the google_sign_in plugin.
/// Only authorization is used: the app never needs to know who you are, so
/// no sign-in client is needed, only an Android OAuth client in the Google
/// Cloud project with the app's package name and signing SHA-1.
class GoogleDriveAuth implements DriveAuth {
  GoogleDriveAuth();

  static Future<void>? _ready;

  Future<GoogleSignInAuthorizationClient> _client() async {
    await (_ready ??= GoogleSignIn.instance.initialize());
    return GoogleSignIn.instance.authorizationClient;
  }

  @override
  Future<String?> token({required bool interactive}) async {
    try {
      final client = await _client();
      if (!interactive) return (await client.authorizationForScopes(const [DriveClient.scope]))?.accessToken;
      return (await client.authorizeScopes(const [DriveClient.scope])).accessToken;
    } on GoogleSignInException catch (e, st) {
      log('Google authorization failed', error: e, stackTrace: st);
      switch (e.code) {
        case GoogleSignInExceptionCode.canceled:
        case GoogleSignInExceptionCode.interrupted:
          return null;
        case GoogleSignInExceptionCode.clientConfigurationError:
        case GoogleSignInExceptionCode.providerConfigurationError:
          throw const DriveAuthException(_setupMessage);
        case GoogleSignInExceptionCode.uiUnavailable:
          throw const DriveAuthException('Google sign-in couldn\'t open. Try again with the app open.');
        default:
          // A wrong package name or SHA-1 comes back from Play services as
          // DEVELOPER_ERROR, status 10.
          final text = '${e.description}';
          if (text.contains('DEVELOPER_ERROR') || RegExp(r'\b10:').hasMatch(text)) {
            throw const DriveAuthException(_setupMessage);
          }
          throw const DriveAuthException('Google didn\'t give access to Drive. Check your connection and try again.');
      }
    }
  }

  static const _setupMessage =
      'Google sign-in isn\'t set up for this copy of the app yet. The README says how to add it in Google Cloud.';

  @override
  Future<void> forget(String token) async {
    await _client();
    await GoogleSignIn.instance.authorizationClient.clearAuthorizationToken(accessToken: token);
  }
}
