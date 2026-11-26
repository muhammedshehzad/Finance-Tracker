import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import 'receipt_entry.dart';
import 'transaction_form_page.dart';
import 'voice_entry_sheet.dart';

/// One floating bar with the three ways to add: speak, a payment screenshot,
/// or type. Sits centred so it never covers the amounts on the right edge.
/// Use with [FloatingActionButtonLocation.centerFloat].
class EntryFabs extends ConsumerWidget {
  const EntryFabs({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer,
      elevation: 3,
      shadowColor: scheme.shadow.withValues(alpha: 0.4),
      shape: const StadiumBorder(),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Add by voice',
              color: scheme.onPrimaryContainer,
              onPressed: () => showVoiceEntrySheet(context),
              icon: const Icon(Icons.mic_none),
            ),
            GestureDetector(
              onLongPress: () => startReceiptEntry(context, ref, source: ImageSource.camera),
              child: IconButton(
                tooltip: 'Add from payment screenshot (hold for camera)',
                color: scheme.onPrimaryContainer,
                onPressed: () => startReceiptEntry(context, ref),
                icon: const Icon(Icons.document_scanner_outlined),
              ),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: 'Add entry',
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                ),
                onPressed: () =>
                    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TransactionFormPage())),
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
