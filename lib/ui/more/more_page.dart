import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/ai/gemini_config.dart';
import '../../services/csv_export.dart';
import '../../services/lock/app_lock_service.dart';
import '../../state/providers.dart';
import '../backup/auto_backup_page.dart';
import '../backup/restore_flow.dart';
import '../budgets/budget_settings_page.dart';
import '../capture/capture_settings_page.dart';
import '../capture/captured_payments_page.dart';
import '../categories/categories_page.dart';
import '../goals/goals_page.dart';
import '../icons.dart';
import '../import/import_page.dart';
import '../recurring/recurring_page.dart';
import '../widgets/common.dart';

/// Settings and less frequent tools: import, export, backup, capture.
class MorePage extends ConsumerWidget {
  const MorePage({super.key});

  /// Writes a backup and opens the share sheet, so it can go to Drive,
  /// Files or a chat with yourself.
  Future<void> _backUp(BuildContext context, WidgetRef ref) async {
    try {
      final json = await ref.read(backupServiceProvider).export();
      final dir = await getTemporaryDirectory();
      final name = 'finance-tracker-backup-${DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now())}.json';
      final file = await File(p.join(dir.path, name)).writeAsString(json);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          title: 'Finance Tracker backup',
        ),
      );
    } catch (e, st) {
      log('Backup failed', error: e, stackTrace: st);
      if (context.mounted) showSnack(context, 'The backup couldn\'t be made. Your entries are unchanged.');
    }
  }

  /// Picks a backup file, says what it holds, and replaces the data on a yes.
  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final picked = await FilePicker.pickFile();
    if (picked == null || !context.mounted) return;
    final String text;
    try {
      text = utf8.decode(await picked.readAsBytes());
    } catch (e, st) {
      log('Could not read the backup file', error: e, stackTrace: st);
      if (context.mounted) showSnack(context, 'This isn\'t a Finance Tracker backup.');
      return;
    }
    if (context.mounted) await confirmAndRestore(context, ref, text);
  }

  void _explainReading(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('How screenshots and voice are read'),
        content: Text(
          GeminiConfig.isConfigured
              ? 'Screenshots you add and voice notes you record are sent to Google\'s Gemini, through Firebase, '
                    'to be read. Nothing else leaves the phone: your entries, accounts and backups stay here.\n\n'
                    'On Gemini\'s free tier, Google may use what is sent to improve its products, and people may '
                    'review it. A Firebase project with billing turned on keeps it out of that.\n\n'
                    'Without a connection, the app reads them on the phone instead.'
              : 'Screenshots and voice are read on the phone, and nothing leaves it.\n\n'
                    'Gemini reads them more accurately. To use it, build the app with a Firebase project, '
                    'as the README explains.',
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(repositoryProvider);
    final txns = await repo.allTxns();
    if (txns.isEmpty) {
      if (context.mounted) showSnack(context, 'Nothing to export yet.');
      return;
    }
    final csv = CsvExport.build(
      txns,
      await repo.accounts(includeArchived: true),
      await repo.categories(includeArchived: true),
    );
    final file = await CsvExport.writeFile(csv);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        title: 'Finance export',
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void open(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        children: [
          ListTile(
            leading: const AppIcon(AppIcons.capture),
            title: const Text('Payment capture'),
            subtitle: const Text('Pick up payments from Google Pay, PhonePe and bank SMS'),
            onTap: () => open(const CaptureSettingsPage()),
            trailing: IconButton(
              tooltip: 'Captured payments',
              icon: const AppIcon(AppIcons.inbox),
              onPressed: () => open(const CapturedPaymentsPage()),
            ),
          ),
          ListTile(
            leading: const AppIcon(AppIcons.recurring),
            title: const Text('Recurring payments'),
            subtitle: const Text('Rent, EMIs, subscriptions, salary'),
            onTap: () => open(const RecurringPage()),
          ),
          ListTile(
            leading: const AppIcon(AppIcons.categories),
            title: const Text('Categories'),
            subtitle: const Text('Names, icons and the words voice entry listens for'),
            onTap: () => open(const CategoriesPage()),
          ),
          ListTile(
            leading: const AppIcon(AppIcons.budget),
            title: const Text('Budgets'),
            onTap: () => open(const BudgetSettingsPage()),
          ),
          ListTile(
            leading: const AppIcon(AppIcons.goal),
            title: const Text('Savings goals'),
            subtitle: const Text('Put money aside toward a trip, a phone or a fund'),
            onTap: () => open(const GoalsPage()),
          ),
          ListTile(
            leading: const AppIcon(AppIcons.importFile),
            title: const Text('Import from Excel'),
            subtitle: const Text('Bring in past entries from an .xlsx or .csv file'),
            onTap: () => open(const ImportPage()),
          ),
          ListTile(
            leading: const AppIcon(AppIcons.exportFile),
            title: const Text('Export to CSV'),
            subtitle: const Text('Opens in Excel or Google Sheets'),
            onTap: () => _export(context, ref),
          ),
          const _AutoBackupTile(),
          ListTile(
            leading: const AppIcon(AppIcons.backup),
            title: const Text('Back up now'),
            subtitle: const Text('Save all your data to one file and share it, e.g. to Google Drive'),
            onTap: () => _backUp(context, ref),
          ),
          ListTile(
            leading: const AppIcon(AppIcons.restore),
            title: const Text('Restore from a backup'),
            subtitle: const Text('Replaces what is in the app. Screenshots aren\'t included'),
            onTap: () => _restore(context, ref),
          ),
          ListTile(
            leading: const AppIcon(AppIcons.drive),
            title: const Text('Restore from Google Drive'),
            subtitle: const Text('Pick one of the weekly backups saved there'),
            onTap: () => restoreFromDrive(context, ref),
          ),
          const Divider(),
          const _AppLockTile(),
          ListTile(
            leading: const AppIcon(AppIcons.ai),
            title: const Text('Reading screenshots and voice'),
            subtitle: Text(
              GeminiConfig.isConfigured
                  ? 'Gemini reads them, so they are sent to Google'
                  : 'Read on the phone. Nothing leaves it',
            ),
            onTap: () => _explainReading(context),
          ),
          const ListTile(
            leading: AppIcon(AppIcons.privacy),
            title: Text('Your entries stay on this phone'),
            subtitle: Text('Back up regularly: uninstalling the app deletes its data.'),
          ),
        ],
      ),
    );
  }
}

/// Turns app lock on or off. Either way the phone's screen lock is asked
/// for first, so only the phone's owner can change it.
class _AppLockTile extends ConsumerWidget {
  const _AppLockTile();

  Future<void> _toggle(BuildContext context, WidgetRef ref, bool on) async {
    final lock = ref.read(appLockServiceProvider);
    if (on && !await lock.isAvailable()) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Set a screen lock first'),
          content: const Text(
            'App lock uses your phone\'s own fingerprint, PIN or pattern. Add one in your phone\'s '
            'Settings, under Security, then turn this on.',
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );
      return;
    }
    final result = await lock.unlock(on ? 'Turn on app lock' : 'Turn off app lock');
    if (!context.mounted) return;
    switch (result) {
      case UnlockResult.unlocked:
        await ref.read(appLockProvider.notifier).set(on);
        if (context.mounted) {
          showSnack(context, on ? 'Finance Tracker now asks for your fingerprint or PIN.' : 'App lock is off.');
        }
      case UnlockResult.cancelled:
        break;
      case UnlockResult.noScreenLock:
        showSnack(context, 'Your phone has no screen lock, so app lock can\'t be used.');
      case UnlockResult.lockedOut:
        showSnack(context, 'Too many tries. Wait a moment, then try again.');
      case UnlockResult.failed:
        showSnack(context, 'The phone couldn\'t check your screen lock. Try again.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(appLockProvider).value ?? false;
    return SwitchListTile(
      secondary: const AppIcon(AppIcons.lock),
      title: const Text('App lock'),
      subtitle: const Text('Ask for your fingerprint or phone PIN when the app opens'),
      value: on,
      onChanged: (v) => _toggle(context, ref, v),
    );
  }
}

/// Opens automatic backup, with how it stands in the subtitle.
class _AutoBackupTile extends ConsumerWidget {
  const _AutoBackupTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folder = ref.watch(autoBackupProvider).value;
    final drive = ref.watch(driveBackupProvider).value;
    final scheme = Theme.of(context).colorScheme;
    final folderOn = folder?.on ?? false;
    final driveOn = drive?.on ?? false;
    final failed = folder?.error != null || drive?.error != null;
    final where = [if (folderOn) folder!.folderName ?? 'your folder', if (driveOn) 'Google Drive'].join(' and ');
    return ListTile(
      leading: const AppIcon(AppIcons.autoBackup),
      title: const Text('Automatic backup'),
      subtitle: Text(
        !folderOn && !driveOn
            ? 'Off. Save a backup to a folder or Google Drive every week'
            : failed
            ? 'The last backup failed. Tap to see why'
            : 'Every week to $where',
        style: failed ? TextStyle(color: scheme.error) : null,
      ),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AutoBackupPage())),
    );
  }
}
