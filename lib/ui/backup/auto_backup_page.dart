import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/dates.dart';
import '../../services/backup/auto_backup_service.dart';
import '../../state/providers.dart';
import '../icons.dart';
import '../motion.dart';
import '../widgets/common.dart';

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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
                              value: s.on,
                              child: Text(
                                s.on ? 'Backing up every week' : 'Automatic backup is off',
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
                onTap: _busy ? null : () => _run(notifier.turnOff, done: 'Automatic backup is off.'),
              ),
            ],
            section('Your Google account'),
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
