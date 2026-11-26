import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';

import '../receipt_parser.dart';
import 'gemini_config.dart';
import 'gemini_receipt.dart';

/// Reads payment screenshots and voice clips with Gemini, through Firebase
/// AI Logic and the Gemini Developer API.
///
/// The app holds no Gemini key: Firebase vouches for each request with an
/// App Check token for this app.
/// Every method returns null when Gemini isn't set up for this build, and
/// throws when a request fails, so callers can fall back to on-device
/// reading.
class GeminiService {
  Future<bool>? _ready;

  static const _timeout = Duration(seconds: 30);

  static const _receiptInstruction = '''
You read screenshots of Indian UPI payment apps such as Google Pay, PhonePe, Paytm, BHIM and bank apps.
Report only what the screenshot shows. Use null for anything that isn't visible, and never guess.
- amount: the payment amount in rupees as a number, e.g. 4000 for ₹4,000 or 249.5 for ₹249.50.
- direction: "paid" when the phone's owner sent money, "received" when they got it.
- payee: the other party's name exactly as shown, without the UPI id.
- payeeUpiId: the other party's UPI id, such as name@okaxis.
- upiRef: the UPI transaction id, UTR or reference number, without spaces.
- dateTime: the payment's local date and time as YYYY-MM-DDTHH:MM.
- status: "success", "failed" or "pending" as the screen shows.
- app: the app that made the screenshot, e.g. Google Pay.''';

  static const _voiceInstruction = '''
Transcribe a short voice note about money the speaker spent, paid, lent or received.
The speaker is in India and may mix English with Hindi or another Indian language. Write the transcript in English.
Write every amount as digits with no currency sign or commas: "two thousand five hundred" becomes 2500, "fifty rupees" becomes 50.
Keep item, people and place names as said, and join separate items with " and ".
Reply with the transcript only. Reply with nothing if there is no speech.''';

  static final _receiptSchema = Schema.object(
    properties: {
      'amount': Schema.number(nullable: true),
      'direction': Schema.enumString(enumValues: ['paid', 'received', 'unknown']),
      'payee': Schema.string(nullable: true),
      'payeeUpiId': Schema.string(nullable: true),
      'upiRef': Schema.string(nullable: true),
      'dateTime': Schema.string(nullable: true),
      'status': Schema.enumString(enumValues: ['success', 'failed', 'pending', 'unknown']),
      'app': Schema.string(nullable: true),
    },
  );

  /// Whether Gemini can be used: the build has a Firebase project and
  /// Firebase started. Starts Firebase on the first call.
  Future<bool> isAvailable() => _ready ??= _start();

  Future<bool> _start() async {
    if (!GeminiConfig.isConfigured) return false;
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp(options: GeminiConfig.options);
      await FirebaseAppCheck.instance.activate(
        providerAndroid: GeminiConfig.appCheckDebugToken.isEmpty
            ? const AndroidPlayIntegrityProvider()
            : const AndroidDebugProvider(debugToken: GeminiConfig.appCheckDebugToken),
      );
      return true;
    } catch (e, st) {
      log('Firebase did not start, so Gemini is off', error: e, stackTrace: st);
      return false;
    }
  }

  GenerativeModel _model(String instruction, {Schema? schema}) => FirebaseAI.googleAI().generativeModel(
    model: GeminiConfig.model,
    systemInstruction: Content.system(instruction),
    generationConfig: GenerationConfig(
      temperature: 0,
      responseMimeType: schema == null ? null : 'application/json',
      responseSchema: schema,
    ),
  );

  /// Reads a payment screenshot. [mimeType] is image/jpeg, image/png or
  /// image/webp.
  Future<ReceiptParseResult?> readReceipt(Uint8List image, String mimeType) async {
    if (!await isAvailable()) return null;
    final response = await _model(_receiptInstruction, schema: _receiptSchema)
        .generateContent([
          Content.multi([TextPart('Read this payment screenshot.'), InlineDataPart(mimeType, image)]),
        ])
        .timeout(_timeout);
    final text = response.text;
    if (text == null) return null;
    final json = jsonDecode(text);
    if (json is! Map<String, Object?>) return null;
    return receiptFromGemini(json, now: DateTime.now());
  }

  /// Turns a recorded voice note into text for the voice parser. Returns
  /// null when nothing was said.
  Future<String?> transcribe(Uint8List audio, String mimeType) async {
    if (!await isAvailable()) return null;
    final response = await _model(_voiceInstruction)
        .generateContent([
          Content.multi([TextPart('Transcribe this voice note.'), InlineDataPart(mimeType, audio)]),
        ])
        .timeout(_timeout);
    final text = response.text?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}
