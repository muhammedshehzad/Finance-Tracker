import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Thin wrapper over speech_to_text, set up for Indian English.
class VoiceService {
  VoiceService({SpeechToText? speech}) : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;
  bool _ready = false;

  bool get isListening => _speech.isListening;

  /// Asks for the microphone permission the first time. Returns false when
  /// speech recognition isn't available or the user declined.
  Future<bool> init({void Function(String error)? onError, void Function(String status)? onStatus}) async {
    if (_ready) return true;
    _ready = await _speech.initialize(onError: (e) => onError?.call(e.errorMsg), onStatus: (s) => onStatus?.call(s));
    return _ready;
  }

  /// Picks en-IN when the device has it, so amounts and Indian names are
  /// recognised better; otherwise the device default.
  Future<String?> _localeId() async {
    final locales = await _speech.locales();
    for (final l in locales) {
      if (l.localeId.toLowerCase().replaceAll('-', '_') == 'en_in') return l.localeId;
    }
    return null;
  }

  Future<void> listen({required void Function(String words, bool isFinal) onResult}) async {
    final locale = await _localeId();
    await _speech.listen(
      onResult: (SpeechRecognitionResult r) => onResult(r.recognizedWords, r.finalResult),
      listenOptions: SpeechListenOptions(
        localeId: locale,
        partialResults: true,
        cancelOnError: true,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 4),
        listenMode: ListenMode.dictation,
      ),
    );
  }

  Future<void> stop() => _speech.stop();

  Future<void> cancel() => _speech.cancel();
}
