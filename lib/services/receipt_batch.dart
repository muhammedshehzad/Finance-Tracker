import '../data/models/txn.dart';
import 'receipt_parser.dart';

/// An entry that looks like the same payment as [r], or null.
///
/// Payment history screenshots rarely show a UPI reference, so this matches
/// on what they do show: the same amount and direction on the same day.
/// When both sides name the other party, they must share a word too, so
/// two different ₹20 teas on one day aren't taken for each other.
Txn? likelyDuplicate(ReceiptParseResult r, TxnType type, Iterable<Txn> sameDay) {
  if (r.amountPaise == null) return null;
  final theirWords = _words(r.payee);
  for (final t in sameDay) {
    if (t.type != type || t.amount != r.amountPaise) continue;
    final ourWords = _words(t.payee ?? (t.note.isEmpty ? null : t.note));
    if (theirWords.isEmpty || ourWords.isEmpty || theirWords.any(ourWords.contains)) return t;
  }
  return null;
}

Set<String> _words(String? name) =>
    name == null ? const {} : name.toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((w) => w.length >= 3).toSet();
