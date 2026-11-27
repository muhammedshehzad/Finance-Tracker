import 'dart:developer';
import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'ai/gemini_service.dart';
import 'receipt_parser.dart';

/// A stored screenshot and the payments read from it.
class ScannedReceipt {
  const ScannedReceipt({required this.imagePath, required this.results});

  /// Copy of the screenshot inside the app's own storage.
  final String imagePath;

  /// One payment for a receipt, several for a payment history. Never empty.
  final List<ReceiptParseResult> results;

  ReceiptParseResult get result => results.first;
}

/// Picks a payment screenshot, keeps a private copy, and reads it.
///
/// Gemini reads it when the build has it set up, and on-device ML Kit text
/// recognition reads it otherwise, or when Gemini fails or finds no amount.
class ReceiptScanner {
  ReceiptScanner({ImagePicker? picker, this.parser = const ReceiptParser(), this.gemini})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;
  final ReceiptParser parser;
  final GeminiService? gemini;

  /// Returns null when the user backs out of the picker.
  Future<ScannedReceipt?> pickAndScan({ImageSource source = ImageSource.gallery}) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 92);
    if (picked == null) return null;
    final stored = await _storeCopy(File(picked.path));
    return ScannedReceipt(imagePath: stored.path, results: await read(stored.path));
  }

  /// Reads the screenshot with Gemini, falling back to the phone, which
  /// reads one payment only.
  Future<List<ReceiptParseResult>> read(String imagePath) async {
    final ai = gemini;
    if (ai != null) {
      try {
        final results = await ai.readReceipts(await File(imagePath).readAsBytes(), _mimeType(imagePath));
        if (results != null && results.isNotEmpty) return results;
      } catch (e, st) {
        log('Gemini could not read the screenshot, reading it on the phone', error: e, stackTrace: st);
      }
    }
    return [parser.parse(await recognise(imagePath))];
  }

  static String _mimeType(String path) => switch (p.extension(path).toLowerCase()) {
    '.png' => 'image/png',
    '.webp' => 'image/webp',
    _ => 'image/jpeg',
  };

  /// Reads the text in the image, line by line in ML Kit's reading order.
  Future<String> recognise(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final recognised = await recognizer.processImage(InputImage.fromFilePath(imagePath));
      return recognised.blocks.expand((b) => b.lines).map((l) => l.text).join('\n');
    } finally {
      await recognizer.close();
    }
  }

  static Future<Directory> receiptsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'receipts'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _storeCopy(File source) async {
    final dir = await receiptsDir();
    final ext = p.extension(source.path).isEmpty ? '.jpg' : p.extension(source.path);
    final name = 'receipt_${DateTime.now().millisecondsSinceEpoch}$ext';
    return source.copy(p.join(dir.path, name));
  }

  /// Removes a stored screenshot, e.g. when the user discards the entry.
  static Future<void> deleteStored(String? path) async {
    if (path == null) return;
    final f = File(path);
    if (await f.exists()) await f.delete();
  }
}
