import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// A notification the Android listener kept, not yet parsed.
class RawNotification {
  factory RawNotification.fromJson(Map<String, Object?> j) => RawNotification(
    key: j['key'] as String,
    package: j['package'] as String,
    title: (j['title'] as String?) ?? '',
    text: (j['text'] as String?) ?? '',
    postedAt: DateTime.fromMillisecondsSinceEpoch((j['postedAt'] as num).toInt()),
  );

  const RawNotification({
    required this.key,
    required this.package,
    required this.title,
    required this.text,
    required this.postedAt,
  });

  final String key;
  final String package;
  final String title;
  final String text;
  final DateTime postedAt;
}

/// Talks to the native notification listener. Android only.
class CaptureChannel {
  const CaptureChannel();

  static const _channel = MethodChannel('finance_tracker/capture');

  bool get supported => Platform.isAndroid;

  Future<bool> isEnabled() async => supported && (await _channel.invokeMethod<bool>('isEnabled') ?? false);

  Future<void> openSettings() => _channel.invokeMethod<void>('openSettings');

  /// Everything the listener kept since the last call, and clears it.
  /// Lines that fail to decode are skipped.
  Future<List<RawNotification>> drain() async {
    if (!supported) return const [];
    final lines = await _channel.invokeListMethod<String>('drain') ?? const [];
    return [for (final l in lines) ?_decode(l)];
  }

  static RawNotification? _decode(String line) {
    try {
      return RawNotification.fromJson(jsonDecode(line) as Map<String, Object?>);
    } catch (_) {
      return null;
    }
  }

  /// Null until the user has chosen sources once.
  Future<Set<String>?> packages() async {
    if (!supported) return null;
    final list = await _channel.invokeListMethod<String>('getPackages');
    return list?.toSet();
  }

  Future<void> setPackages(Set<String> packages) =>
      _channel.invokeMethod<void>('setPackages', {'packages': packages.toList()});
}
