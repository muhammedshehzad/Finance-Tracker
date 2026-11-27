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

import '../../core/dates.dart';
import '../../services/ai/gemini_config.dart';
import '../../services/backup_service.dart';
import '../../services/csv_export.dart';
import '../../state/providers.dart';
import '../budgets/budget_settings_page.dart';
import '../capture/capture_settings_page.dart';
import '../capture/captured_payments_page.dart';
import '../categories/categories_page.dart';
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

  /// Picks a backup, says what it holds, and replaces the data on a yes.
  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final picked = await FilePicker.pickFile();
    if (picked == null || !context.mounted) return;
    final String text;
    final BackupInfo info;
    try {
      text = utf8.decode(await picked.readAsBytes());
      info = ref.read(backupServiceProvider).inspect(text);
    } on BackupException catch (e) {
      if (context.mounted) showSnack(context, e.message);
      return;
    } catch (e, st) {
      log('Could not read the backup file', error: e, stackTrace: st);
      if (context.mounted) showSnack(context, 'This isn\'t a Finance Tracker backup.');
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
          ListTile(
            leading: const AppIcon(AppIcons.backup),
            title: const Text('Back up'),
            subtitle: const Text('Save all your data to one file, e.g. in Google Drive'),
            onTap: () => _backUp(context, ref),
          ),
          ListTile(
            leading: const AppIcon(AppIcons.restore),
            title: const Text('Restore from a backup'),
            subtitle: const Text('Replaces what is in the app. Screenshots aren\'t included'),
            onTap: () => _restore(context, ref),
          ),
          const Divider(),
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
