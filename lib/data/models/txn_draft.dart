import 'txn.dart';

/// Values to prefill the entry form with, from a screenshot, voice or a
/// recurring rule. Nothing here is saved until the user taps Save.
class TxnDraft {
  const TxnDraft({
    this.type = TxnType.expense,
    this.amount,
    this.date,
    this.accountId,
    this.toAccountId,
    this.categoryId,
    this.note = '',
    this.description = '',
    this.payee,
    this.upiRef,
    this.attachmentPath,
    this.source = TxnSource.manual,
    this.warning,
  });

  final TxnType type;
  final int? amount;
  final DateTime? date;
  final int? accountId;
  final int? toAccountId;
  final int? categoryId;
  final String note;
  final String description;
  final String? payee;
  final String? upiRef;
  final String? attachmentPath;
  final TxnSource source;

  /// Shown above the form, e.g. "The screenshot says this payment failed".
  final String? warning;
}
