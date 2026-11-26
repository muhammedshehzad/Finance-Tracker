/// Writes `firebase.env.json` from the `google-services.json` that the
/// Firebase console gives you, so builds can turn on Gemini with
/// `--dart-define-from-file=firebase.env.json`.
///
/// Usage: `dart run tool/firebase_env.dart path/to/google-services.json [app-check-debug-token]`
library;

import 'dart:convert';
import 'dart:io';

const _packageName = 'com.shehzad.finance_tracker';

void main(List<String> args) {
  if (args.isEmpty || args.length > 2) {
    stderr.writeln('Usage: dart run tool/firebase_env.dart path/to/google-services.json [app-check-debug-token]');
    exit(64);
  }
  final services = jsonDecode(File(args.first).readAsStringSync()) as Map<String, dynamic>;
  final project = services['project_info'] as Map<String, dynamic>;
  final client = (services['client'] as List).cast<Map<String, dynamic>>().where((c) {
    final android = (c['client_info'] as Map<String, dynamic>)['android_client_info'] as Map<String, dynamic>;
    return android['package_name'] == _packageName;
  }).firstOrNull;
  if (client == null) {
    stderr.writeln('No Android app with the package $_packageName in that file. Add it in the Firebase console.');
    exit(1);
  }
  final env = {
    'FIREBASE_API_KEY': ((client['api_key'] as List).first as Map<String, dynamic>)['current_key'],
    'FIREBASE_APP_ID': (client['client_info'] as Map<String, dynamic>)['mobilesdk_app_id'],
    'FIREBASE_PROJECT_ID': project['project_id'],
    'FIREBASE_SENDER_ID': project['project_number'],
    if (args.length == 2) 'FIREBASE_APPCHECK_DEBUG_TOKEN': args[1],
  };
  File('firebase.env.json').writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(env)}\n');
  stdout.writeln('Wrote firebase.env.json. Keep it out of git; .gitignore already does.');
}
