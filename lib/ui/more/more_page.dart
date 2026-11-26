import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/csv_export.dart';
import '../../state/providers.dart';
import '../budgets/budget_settings_page.dart';
import '../capture/capture_settings_page.dart';
import '../capture/captured_payments_page.dart';
import '../categories/categories_page.dart';
import '../import/import_page.dart';
import '../recurring/recurring_page.dart';
import '../widgets/common.dart';

/// Settings and less frequent tools: import, export, capture, categories.
class MorePage extends ConsumerWidget {
  const MorePage({super.key});

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
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('Payment capture'),
            subtitle: const Text('Pick up payments from Google Pay, PhonePe and bank SMS'),
            onTap: () => open(const CaptureSettingsPage()),
            trailing: IconButton(
              tooltip: 'Captured payments',
              icon: const Icon(Icons.inbox_outlined),
              onPressed: () => open(const CapturedPaymentsPage()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.event_repeat),
            title: const Text('Recurring payments'),
            subtitle: const Text('Rent, EMIs, subscriptions, salary'),
            onTap: () => open(const RecurringPage()),
          ),
          ListTile(
            leading: const Icon(Icons.category_outlined),
            title: const Text('Categories'),
            subtitle: const Text('Names, icons and the words voice entry listens for'),
            onTap: () => open(const CategoriesPage()),
          ),
          ListTile(
            leading: const Icon(Icons.savings_outlined),
            title: const Text('Budgets'),
            onTap: () => open(const BudgetSettingsPage()),
          ),
          ListTile(
            leading: const Icon(Icons.upload_file_outlined),
            title: const Text('Import from Excel'),
            subtitle: const Text('Bring in past entries from an .xlsx or .csv file'),
            onTap: () => open(const ImportPage()),
          ),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: const Text('Export to CSV'),
            subtitle: const Text('Opens in Excel or Google Sheets'),
            onTap: () => _export(context, ref),
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('Your data stays on this phone'),
            subtitle: Text(
              'Entries, screenshots and voice are processed on the device. '
              'Export regularly: uninstalling the app deletes its data.',
            ),
          ),
        ],
      ),
    );
  }
}
