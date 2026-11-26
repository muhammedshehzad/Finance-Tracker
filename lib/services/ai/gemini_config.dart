import 'package:firebase_core/firebase_core.dart';

/// Firebase settings for Gemini, set at build time with
/// `--dart-define-from-file=firebase.env.json`.
///
/// A build without them reads screenshots and voice on the phone only.
class GeminiConfig {
  const GeminiConfig._();

  static const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const _appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const _senderId = String.fromEnvironment('FIREBASE_SENDER_ID');

  /// An App Check debug token registered in the Firebase console. Firebase
  /// blocks AI Logic requests without App Check, and Play Integrity only
  /// vouches for apps installed from Play, so a sideloaded build needs this.
  static const appCheckDebugToken = String.fromEnvironment('FIREBASE_APPCHECK_DEBUG_TOKEN');

  /// The Gemini model that reads screenshots and voice clips.
  static const model = String.fromEnvironment('GEMINI_MODEL', defaultValue: 'gemini-3.5-flash-lite');

  /// Whether this build was given a Firebase project.
  static bool get isConfigured => _apiKey.isNotEmpty && _appId.isNotEmpty && _projectId.isNotEmpty;

  static FirebaseOptions get options =>
      const FirebaseOptions(apiKey: _apiKey, appId: _appId, messagingSenderId: _senderId, projectId: _projectId);
}
