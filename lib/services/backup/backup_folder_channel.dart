import 'package:flutter/services.dart';

/// A folder the user chose for backups.
class PickedFolder {
  const PickedFolder(this.uri, this.name);

  /// Android's address for the folder, kept to write there later.
  final String uri;

  /// The folder's name, to show.
  final String name;
}

/// Talks to the Android side that writes backups into a chosen folder.
class BackupFolderChannel {
  const BackupFolderChannel();

  static const _channel = MethodChannel('finance_tracker/backup_folder');

  /// Opens Android's folder picker. Null when nothing was chosen.
  Future<PickedFolder?> pick() async {
    final picked = await _channel.invokeMapMethod<String, String>('pick');
    if (picked == null) return null;
    return PickedFolder(picked['uri']!, picked['name']!);
  }

  /// Writes [text] as [name] in the folder and deletes this app's older
  /// backups there beyond [keep]. Returns the name the file got.
  Future<String> write(String uri, String name, String text, {required int keep}) async =>
      (await _channel.invokeMethod<String>('write', {'uri': uri, 'name': name, 'text': text, 'keep': keep}))!;

  /// Whether the app can still write to the folder. Android drops the
  /// permission when the folder is deleted, or the app is reinstalled.
  Future<bool> hasAccess(String uri) async => await _channel.invokeMethod<bool>('hasAccess', {'uri': uri}) ?? false;

  /// Gives up the permission to the folder.
  Future<void> release(String uri) => _channel.invokeMethod<void>('release', {'uri': uri});
}
