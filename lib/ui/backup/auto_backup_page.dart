import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/dates.dart';
import '../../services/backup/auto_backup_service.dart';
import '../../services/backup/drive_auth.dart';
import '../../services/backup/drive_backup_service.dart';
import '../../state/providers.dart';
import '../icons.dart';
import '../motion.dart';
import '../widgets/common.dart';
import 'restore_flow.dart';

/// Turns weekly backups on, shows where they go and how the last one went.
class AutoBackupPage extends ConsumerStatefulWidget {
  const AutoBackupPage({super.key});

  @override
  ConsumerState<AutoBackupPage> createState() => _AutoBackupPageState();
}

class _AutoBackupPageState extends ConsumerState<AutoBackupPage> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (done != null && mounted) showSnack(context, done);
    } on AutoBackupException catch (e) {
      if (mounted) showSnack(context, e.message);
    } on PlatformException {
      if (mounted) showSnack(context, 'The folder picker couldn\'t open. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _choose() => _run(() async {
    final chosen = await ref.read(autoBackupProvider.notifier).chooseFolder();
    if (chosen && mounted) showSnack(context, 'Backed up. The next one is due in a week.');
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final notifier = ref.read(autoBackupProvider.notifier);

    Widget section(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
      child: Text(title, style: t.titleSmall?.copyWith(color: scheme.primary)),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Automatic backup')),
      body: AsyncBody(
        value: ref.watch(autoBackupProvider),
        builder: (s) => ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            section('Folder on this phone'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Card.filled(
                color: s.on && s.error == null ? scheme.primaryContainer : scheme.surfaceContainerHigh,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          AppIcon(
                            s.error != null ? AppIcons.warning : (s.on ? AppIcons.done : AppIcons.autoBackup),
                            color: s.error != null ? scheme.error : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SwapIn(
                              alignment: Alignment.centerLeft,
                              value: s.on,
                              child: Text(
                                s.on ? 'Backing up to a folder weekly' : 'Folder backup is off',
                                style: t.titleMedium,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        s.on
                            ? 'A backup file goes into ${s.folderName ?? 'your folder'} once a week, when you open the app. '
                                  'The newest ${AutoBackupService.keep} are kept.'
                            : 'Pick a folder on your phone, such as Download, and a backup file goes there once a week. '
                                  'Files there stay if the app is uninstalled, so you can restore from them.',
                        style: t.bodyMedium,
                      ),
                      if (s.error != null) ...[
                        const SizedBox(height: 8),
                        Text(s.error!, style: t.bodyMedium?.copyWith(color: scheme.error)),
                      ],
                      const SizedBox(height: 12),
                      if (!s.on)
                        FilledButton.icon(
                          onPressed: _busy ? null : _choose,
                          icon: const AppIcon(AppIcons.folder, size: 20),
                          label: const Text('Choose a folder'),
                        )
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: _busy ? null : () => _run(notifier.backUpNow, done: 'Backed up.'),
                              icon: _busy
                                  ? const AppLoader(size: 18, centered: false)
                                  : const AppIcon(AppIcons.backup, size: 20),
                              label: const Text('Back up now'),
                            ),
                            OutlinedButton(onPressed: _busy ? null : _choose, child: const Text('Change folder')),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (s.on) ...[
              section('Last backup'),
              ListTile(
                leading: const AppIcon(AppIcons.history),
                title: Text(
                  s.lastAt == null ? 'Not yet' : '${fullDateFormat.format(s.lastAt!)}, ${timeFormat.format(s.lastAt!)}',
                ),
                subtitle: s.lastFile == null ? null : Text(s.lastFile!),
              ),
              if (s.nextAt != null)
                ListTile(
                  leading: const AppIcon(AppIcons.calendar),
                  title: const Text('Next one'),
                  subtitle: Text('${fullDateFormat.format(s.nextAt!)} or the first time you open the app after'),
                ),
              ListTile(
                leading: const AppIcon(AppIcons.close),
                title: const Text('Turn off'),
                subtitle: const Text('Backups already in the folder stay there'),
                onTap: _busy ? null : () => _run(notifier.turnOff, done: 'Folder backup is off.'),
              ),
            ],
            section('Google Drive'),
            const _DriveCard(),
            section('Android\'s own backup'),
            const ListTile(
              leading: AppIcon(AppIcons.info),
              title: Text('Android may also back up to your Google account'),
              subtitle: Text(
                'When Backup is on in your phone\'s settings, Android copies the app\'s entries to your Google '
                'account about once a day, while charging on Wi-Fi. Whether it comes back on a new phone depends '
                'on the phone, so treat the weekly file as the copy to rely on.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Turns the Google Drive copy on or off, and restores from it.
class _DriveCard extends ConsumerStatefulWidget {
  const _DriveCard();

  @override
  ConsumerState<_DriveCard> createState() => _DriveCardState();
}

class _DriveCardState extends ConsumerState<_DriveCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (done != null && mounted) showSnack(context, done);
    } on DriveSignInCancelled {
      // The user backed out of Google's screen. Nothing changed.
    } on AutoBackupException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() => _run(() async {
    final connected = await ref.read(driveBackupProvider.notifier).connect();
    if (connected && mounted) showSnack(context, 'Backed up to Google Drive. The next one is due in a week.');
  });

  Future<void> _turnOff() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop backing up to Drive?'),
        content: const Text(
          'The app gives up its access to your Drive. The backups already there stay, so you can still '
          'restore from them after signing in again.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Stop')),
        ],
      ),
    );
    if (ok == true) await _run(ref.read(driveBackupProvider.notifier).turnOff, done: 'Google Drive backup is off.');
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final s = ref.watch(driveBackupProvider).value ?? const DriveBackupStatus();
    final notifier = ref.read(driveBackupProvider.notifier);
    final account = s.account ?? 'your Google account';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Card.filled(
            color: s.on && s.error == null ? scheme.primaryContainer : scheme.surfaceContainerHigh,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AppIcon(
                        s.error != null ? AppIcons.warning : (s.on ? AppIcons.done : AppIcons.drive),
                        color: s.error != null ? scheme.error : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SwapIn(
                          alignment: Alignment.centerLeft,
                          value: s.on,
                          child: Text(
                            s.on ? 'Backing up to Drive weekly' : 'Google Drive backup is off',
                            style: t.titleMedium,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    s.on
                        ? 'Each week a copy goes to a hidden app folder in the Drive of $account. '
                              'The newest ${DriveBackupService.keep} are kept.'
                        : 'Sign in with Google and a copy goes to your Drive each week, so it survives losing '
                              'the phone. It goes to a hidden folder that only this app can open, and the app '
                              'can\'t see anything else in your Drive.',
                    style: t.bodyMedium,
                  ),
                  if (s.error != null) ...[
                    const SizedBox(height: 8),
                    Text(s.error!, style: t.bodyMedium?.copyWith(color: scheme.error)),
                  ],
                  const SizedBox(height: 12),
                  if (!s.on)
                    FilledButton.icon(
                      onPressed: _busy ? null : _connect,
                      icon: _busy
                          ? const AppLoader(size: 18, centered: false)
                          : const AppIcon(AppIcons.drive, size: 20),
                      label: const Text('Sign in with Google'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: _busy ? null : () => _run(notifier.backUpNow, done: 'Backed up to Google Drive.'),
                      icon: _busy
                          ? const AppLoader(size: 18, centered: false)
                          : const AppIcon(AppIcons.backup, size: 20),
                      label: const Text('Back up now'),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (s.on && s.lastAt != null)
          ListTile(
            leading: const AppIcon(AppIcons.history),
            title: const Text('Last copy in Drive'),
            subtitle: Text('${fullDateFormat.format(s.lastAt!)}, ${timeFormat.format(s.lastAt!)}'),
          ),
        ListTile(
          leading: const AppIcon(AppIcons.restore),
          title: const Text('Restore from Google Drive'),
          subtitle: const Text('Pick one of the backups saved there'),
          onTap: _busy ? null : () => restoreFromDrive(context, ref),
        ),
        if (s.on)
          ListTile(
            leading: const AppIcon(AppIcons.close),
            title: const Text('Stop backing up to Drive'),
            subtitle: const Text('Backups already in Drive stay there'),
            onTap: _busy ? null : _turnOff,
          ),
      ],
    );
  }
}
