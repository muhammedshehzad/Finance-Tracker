/// Money out, money in, or money moved between your own accounts.
enum TxnType { expense, income, transfer }

/// Where an entry came from. Shown as a small badge in lists.
enum TxnSource { manual, screenshot, voice, recurring, imported, notification }

/// One money movement. Named Txn to stay clear of sqflite's Transaction.
class Txn {
  factory Txn.fromMap(Map<String, Object?> m) => Txn(
    id: m['id'] as int,
    type: TxnType.values.byName(m['type'] as String),
    amount: m['amount'] as int,
    date: DateTime.fromMillisecondsSinceEpoch(m['date'] as int),
    accountId: m['account_id'] as int,
    categoryId: m['category_id'] as int?,
    toAccountId: m['to_account_id'] as int?,
    note: (m['note'] as String?) ?? '',
    description: (m['description'] as String?) ?? '',
    source: TxnSource.values.byName(m['source'] as String),
    attachmentPath: m['attachment_path'] as String?,
    upiRef: m['upi_ref'] as String?,
    payee: m['payee'] as String?,
    recurringId: m['recurring_id'] as int?,
  );

  const Txn({
    this.id,
    required this.type,
    required this.amount,
    required this.date,
    required this.accountId,
    this.categoryId,
    this.toAccountId,
    this.note = '',
    this.description = '',
    this.source = TxnSource.manual,
    this.attachmentPath,
    this.upiRef,
    this.payee,
    this.recurringId,
  });

  final int? id;
  final TxnType type;

  /// Always positive, in paise. [type] gives the direction.
  final int amount;
  final DateTime date;

  /// For income/expense the account money went into/out of. For a transfer
  /// the account the money left.
  final int accountId;

  /// Null for transfers.
  final int? categoryId;

  /// Destination account, transfers only.
  final int? toAccountId;
  final String note;
  final String description;
  final TxnSource source;

  /// Path of a payment screenshot kept in app storage.
  final String? attachmentPath;

  /// UPI reference / UTR from a payment screenshot. Unique, used to stop the
  /// same payment being recorded twice.
  final String? upiRef;
  final String? payee;
  final int? recurringId;

  Txn copyWith({
    int? id,
    TxnType? type,
    int? amount,
    DateTime? date,
    int? accountId,
    int? categoryId,
    bool clearCategory = false,
    int? toAccountId,
    bool clearToAccount = false,
    String? note,
    String? description,
    TxnSource? source,
    String? attachmentPath,
    String? upiRef,
    String? payee,
    int? recurringId,
  }) => Txn(
    id: id ?? this.id,
    type: type ?? this.type,
    amount: amount ?? this.amount,
    date: date ?? this.date,
    accountId: accountId ?? this.accountId,
    categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
    toAccountId: clearToAccount ? null : (toAccountId ?? this.toAccountId),
    note: note ?? this.note,
    description: description ?? this.description,
    source: source ?? this.source,
    attachmentPath: attachmentPath ?? this.attachmentPath,
    upiRef: upiRef ?? this.upiRef,
    payee: payee ?? this.payee,
    recurringId: recurringId ?? this.recurringId,
  );

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'type': type.name,
    'amount': amount,
    'date': date.millisecondsSinceEpoch,
    'account_id': accountId,
    'category_id': categoryId,
    'to_account_id': toAccountId,
    'note': note,
    'description': description,
    'source': source.name,
    'attachment_path': attachmentPath,
    'upi_ref': (upiRef == null || upiRef!.isEmpty) ? null : upiRef,
    'payee': payee,
    'recurring_id': recurringId,
  };
}
