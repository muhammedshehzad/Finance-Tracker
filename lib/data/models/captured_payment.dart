import '../../services/capture/notification_parser.dart';

/// Where a captured payment stands.
enum CaptureStatus {
  /// Waiting for the user to add or ignore it.
  pending,

  /// Saved as an entry.
  added,

  /// Dismissed by the user.
  ignored,

  /// Its UPI reference was already recorded, so it was set aside without
  /// asking.
  duplicate,
}

/// A payment read from a notification, kept until the user adds or ignores it.
class CapturedPayment {
  factory CapturedPayment.fromMap(Map<String, Object?> m) => CapturedPayment(
    id: m['id'] as int,
    key: m['key'] as String,
    package: m['package'] as String,
    postedAt: DateTime.fromMillisecondsSinceEpoch(m['posted_at'] as int),
    direction: PaymentDirection.values.byName(m['direction'] as String),
    amount: m['amount'] as int,
    title: (m['title'] as String?) ?? '',
    text: (m['body'] as String?) ?? '',
    counterparty: m['counterparty'] as String?,
    upiRef: m['upi_ref'] as String?,
    accountHint: m['account_hint'] as String?,
    status: CaptureStatus.values.byName(m['status'] as String),
    txnId: m['txn_id'] as int?,
    possibleDuplicateOf: m['duplicate_of'] as int?,
  );

  const CapturedPayment({
    this.id,
    required this.key,
    required this.package,
    required this.postedAt,
    required this.direction,
    required this.amount,
    this.title = '',
    this.text = '',
    this.counterparty,
    this.upiRef,
    this.accountHint,
    this.status = CaptureStatus.pending,
    this.txnId,
    this.possibleDuplicateOf,
  });

  final int? id;

  /// Identifies one notification, so a re-posted notification is stored once.
  final String key;
  final String package;
  final DateTime postedAt;
  final PaymentDirection direction;
  final int amount;
  final String title;
  final String text;
  final String? counterparty;
  final String? upiRef;
  final String? accountHint;
  final CaptureStatus status;
  final int? txnId;

  /// Another capture with the same amount and direction a few minutes apart,
  /// e.g. the Google Pay notification and the bank SMS for one payment.
  final int? possibleDuplicateOf;

  String get sourceLabel => PaymentSource.byPackage(package)?.label ?? package;

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'key': key,
    'package': package,
    'posted_at': postedAt.millisecondsSinceEpoch,
    'direction': direction.name,
    'amount': amount,
    'title': title,
    'body': text,
    'counterparty': counterparty,
    'upi_ref': upiRef,
    'account_hint': accountHint,
    'status': status.name,
    'txn_id': txnId,
    'duplicate_of': possibleDuplicateOf,
  };
}
