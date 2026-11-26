import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'receipt_parser.dart';

/// A stored screenshot and what was read from it.
class ScannedReceipt {
  const ScannedReceipt({required this.imagePath, required this.result});

  /// Copy of the screenshot inside the app's own storage.
  final String imagePath;
  final ReceiptParseResult result;
}

/// Picks a payment screenshot, keeps a private copy, and reads it with
/// on-device ML Kit text recognition. Nothing leaves the phone.
class ReceiptScanner {
  ReceiptScanner({ImagePicker? picker, this.parser = const ReceiptParser()}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;
  final ReceiptParser parser;

  /// Returns null when the user backs out of the picker.
  Future<ScannedReceipt?> pickAndScan({ImageSource source = ImageSource.gallery}) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 92);
    if (picked == null) return null;
    final stored = await _storeCopy(File(picked.path));
    final text = await recognise(stored.path);
    return ScannedReceipt(imagePath: stored.path, result: parser.parse(text));
  }

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
