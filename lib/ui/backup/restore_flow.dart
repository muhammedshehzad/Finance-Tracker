import 'dart:async';
import 'dart:developer';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/dates.dart';
import '../../services/backup/auto_backup_service.dart';
import '../../services/backup/drive_auth.dart';
import '../../services/backup/drive_client.dart';
import '../../services/backup_service.dart';
import '../../state/providers.dart';
import '../icons.dart';
import '../motion.dart';
import '../widgets/common.dart';

/// Says what a backup holds and replaces the app's data with it on a yes.
Future<void> confirmAndRestore(BuildContext context, WidgetRef ref, String text) async {
  final BackupInfo info;
  try {
    info = ref.read(backupServiceProvider).inspect(text);
  } on BackupException catch (e) {
    if (context.mounted) showSnack(context, e.message);
    return;
  }
  if (!context.mounted) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Replace your data?'),
      content: Text(
        'This backup is from ${fullDateFormat.format(info.createdAt)} and has ${info.entryCount} '
        '${info.entryCount == 1 ? 'entry' : 'entries'}. Everything in the app now will be replaced by it.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Replace')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await ref.read(actionsProvider).restoreBackup(text);
    if (context.mounted) showSnack(context, 'Restored ${info.entryCount} entries.');
  } catch (e, st) {
    log('Restore failed', error: e, stackTrace: st);
    if (context.mounted) showSnack(context, 'Nothing was restored. Your entries are unchanged.');
  }
}

/// Lists the backups in Google Drive, and restores the one picked. Google
/// may ask to sign in first, as it will on a new phone.
Future<void> restoreFromDrive(BuildContext context, WidgetRef ref) async {
  final service = ref.read(driveBackupServiceProvider);
  final files = await _withProgress(context, service.backups);
  if (files == null || !context.mounted) return;
  if (files.isEmpty) {
    showSnack(context, 'There are no backups in Google Drive for this account yet.');
    return;
  }
  final picked = await showModalBottomSheet<DriveFile>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Backups in Google Drive', style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final f in files)
            ListTile(
              leading: const AppIcon(AppIcons.restore),
              title: Text('${fullDateFormat.format(f.createdAt)}, ${timeFormat.format(f.createdAt)}'),
              subtitle: f.size == null ? null : Text(_size(f.size!)),
              onTap: () => Navigator.pop(context, f),
            ),
        ],
      ),
    ),
  );
  if (picked == null || !context.mounted) return;
  final text = await _withProgress(context, () => service.read(picked));
  if (text == null || !context.mounted) return;
  await confirmAndRestore(context, ref, text);
}

String _size(int bytes) =>
    bytes < 1024 * 1024 ? '${(bytes / 1024).ceil()} KB' : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

/// Runs [action] behind a small progress dialog. Null when it failed or
/// sign-in was cancelled; a failure is shown as a snack.
Future<T?> _withProgress<T>(BuildContext context, Future<T> Function() action) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  var open = true;
  unawaited(_progressDialog(context).whenComplete(() => open = false));
  try {
    return await action();
  } on DriveSignInCancelled {
    return null;
  } on AutoBackupException catch (e) {
    if (context.mounted) showSnack(context, e.message);
    return null;
  } finally {
    if (open) navigator.pop();
  }
}

/// The progress dialog, which can't be dismissed by the user.
Future<void> _progressDialog(BuildContext context) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (context) => const PopScope(
    canPop: false,
    child: AlertDialog(
      content: Row(
        children: [
          AppLoader(size: 24, centered: false),
          SizedBox(width: 16),
          Expanded(child: Text('Talking to Google Drive…')),
        ],
      ),
    ),
  ),
);
