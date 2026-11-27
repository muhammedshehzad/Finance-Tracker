import 'dart:developer';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/models/category.dart';
import '../../data/models/txn.dart';
import '../../data/models/txn_draft.dart';
import '../../services/category_matcher.dart';
import '../../services/receipt_parser.dart';
import '../../services/receipt_scanner.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';
import 'multi_receipt_page.dart';
import 'transaction_form_page.dart';

/// Picks payment screenshots and reads them with Gemini or on the phone.
final receiptScannerProvider = Provider<ReceiptScanner>(
  (ref) => ReceiptScanner(gemini: ref.watch(geminiServiceProvider)),
);

/// Picks a payment screenshot and reads it. Returns null if the user backs
/// out or the image can't be read.
Future<ScannedReceipt?> _scan(BuildContext context, WidgetRef ref, ImageSource source) async {
  try {
    return await _withProgress(context, ref.read(receiptScannerProvider).pickAndScan(source: source));
  } catch (e, st) {
    log('Receipt scan failed', error: e, stackTrace: st);
    if (context.mounted) showSnack(context, 'Couldn\'t read that screenshot. Try another, or enter it by hand.');
    return null;
  }
}

/// Picks a payment screenshot, reads it and turns its first payment into a
/// draft for the entry form. Returns null if the user backs out, the image
/// can't be read, or the payment is already recorded.
Future<TxnDraft?> scanReceiptToDraft(
  BuildContext context,
  WidgetRef ref, {
  ImageSource source = ImageSource.gallery,
}) async {
  final scanned = await _scan(context, ref, source);
  if (scanned == null || !context.mounted) return null;
  return _draftFor(context, ref, scanned);
}

/// The first payment of [scanned] as a draft, after checking its UPI
/// reference isn't recorded already.
Future<TxnDraft?> _draftFor(BuildContext context, WidgetRef ref, ScannedReceipt scanned) async {
  final repo = ref.read(repositoryProvider);
  final lookups = await ref.read(lookupsProvider.future);
  if (!context.mounted) return null;
  final r = scanned.result;

  if (r.upiRef != null) {
    final existing = await repo.findByUpiRef(r.upiRef!);
    if (existing != null) {
      await ReceiptScanner.deleteStored(scanned.imagePath);
      if (!context.mounted) return null;
      final open = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Already recorded'),
          content: Text(
            'This payment (UPI ref ${r.upiRef}) was saved on ${fullDateFormat.format(existing.date)} '
            'for ${formatMoney(existing.amount)}.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Close')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Open it')),
          ],
        ),
      );
      if (open == true && context.mounted) {
        await Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => TransactionFormPage(existing: existing)));
      }
      return null;
    }
  }

  final type = r.direction == ReceiptDirection.received ? TxnType.income : TxnType.expense;
  final kind = type == TxnType.income ? CategoryKind.income : CategoryKind.expense;
  final category = r.payee == null ? null : CategoryMatcher(lookups.categories).match(r.payee!, kind);

  final others = scanned.results.length - 1;
  final String? warning = switch (r.status) {
    _ when others > 0 =>
      'This screenshot has ${others + 1} payments and only the first is filled in. '
          'Add it with the screenshot button to save them all.',
    ReceiptStatus.failed => 'The screenshot says this payment failed. Check before saving.',
    ReceiptStatus.pending => 'The screenshot says this payment is pending.',
    _ when !r.hasAmount => 'Couldn\'t read the amount. Please type it in.',
    _ => null,
  };

  final details = [if (r.app != null) r.app!, if (r.payeeVpa != null) r.payeeVpa!].join(' · ');

  return TxnDraft(
    type: type,
    amount: r.amountPaise,
    date: r.date,
    accountId: lookups.defaultAccount?.id,
    categoryId: category?.id,
    note: r.payee ?? '',
    description: details,
    payee: r.payee,
    upiRef: r.upiRef,
    attachmentPath: scanned.imagePath,
    source: TxnSource.screenshot,
    warning: warning,
  );
}

/// Screenshot → prefilled form, or a list to tick when it shows several
/// payments. Entries are saved only when Save is tapped.
Future<void> startReceiptEntry(BuildContext context, WidgetRef ref, {ImageSource source = ImageSource.gallery}) async {
  final scanned = await _scan(context, ref, source);
  if (scanned == null || !context.mounted) return;
  if (scanned.results.length > 1) {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MultiReceiptPage(scanned: scanned)));
    return;
  }
  final draft = await _draftFor(context, ref, scanned);
  if (draft == null || !context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TransactionFormPage(draft: draft)));
}

Future<T> _withProgress<T>(BuildContext context, Future<T> work) async {
  var shown = false;
  final timer = Future<void>.delayed(const Duration(milliseconds: 600), () {
    if (!context.mounted) return;
    shown = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(children: [CircularProgressIndicator(), SizedBox(width: 16), Text('Reading screenshot…')]),
      ),
    );
  });
  try {
    return await work;
  } finally {
    await timer;
    if (shown && context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
}
