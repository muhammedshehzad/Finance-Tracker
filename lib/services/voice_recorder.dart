import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Records a short voice note to a WAV file for Gemini to transcribe.
///
/// Calls `onDone` once the speaker pauses after talking, or after 30
/// seconds, so a note ends on its own the way the on-device recogniser does.
class VoiceRecorder {
  final _recorder = AudioRecorder();
  StreamSubscription<Amplitude>? _levels;

  static const _speechLevel = -40.0;
  static const _pause = Duration(seconds: 3);
  static const _longest = Duration(seconds: 30);

  /// Starts recording. Returns false when the microphone isn't allowed.
  Future<bool> start({required void Function() onDone}) async {
    if (!await _recorder.hasPermission()) return false;
    final dir = await getTemporaryDirectory();
    final path = p.join(dir.path, 'voice_${DateTime.now().millisecondsSinceEpoch}.wav');
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1), path: path);

    final started = DateTime.now();
    var lastSpeech = started;
    var heardSpeech = false;
    _levels = _recorder.onAmplitudeChanged(const Duration(milliseconds: 200)).listen((level) {
      final now = DateTime.now();
      if (level.current > _speechLevel) {
        heardSpeech = true;
        lastSpeech = now;
      }
      if ((heardSpeech && now.difference(lastSpeech) > _pause) || now.difference(started) > _longest) onDone();
    });
    return true;
  }

  /// Stops and returns the recording, deleting the file. Returns null when
  /// nothing was recorded.
  Future<Uint8List?> stop() async {
    await _levels?.cancel();
    _levels = null;
    final path = await _recorder.stop();
    if (path == null) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    await file.delete();
    return bytes;
  }

  /// Stops recording, throws the recording away and frees the microphone.
  Future<void> dispose() async {
    await _levels?.cancel();
    await _recorder.dispose();
  }
}
