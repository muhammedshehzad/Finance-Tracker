/// Kinds of account. The kind decides how a balance is read:
/// - [cash], [bank], [wallet]: money you hold (asset).
/// - [creditCard]: money you owe. Its balance goes negative as you spend on
///   it; paying the bill is a transfer from a bank account into the card.
/// - [receivable]: money others owe you, e.g. money you lent. Lending is a
///   transfer from your bank/cash into this account, being repaid is a
///   transfer back. Neither is an expense or income.
enum AccountKind {
  cash('Cash'),
  bank('Bank account'),
  wallet('Wallet'),
  creditCard('Credit card'),
  receivable('Lent to others');

  const AccountKind(this.label);
  final String label;

  bool get isLiability => this == AccountKind.creditCard;

  static AccountKind fromName(String name) =>
      AccountKind.values.firstWhere((k) => k.name == name, orElse: () => AccountKind.bank);
}

/// A place money sits: cash, a bank account, a wallet, a card or a loan.
class Account {
  factory Account.fromMap(Map<String, Object?> m) => Account(
    id: m['id'] as int,
    name: m['name'] as String,
    kind: AccountKind.fromName(m['kind'] as String),
    openingBalance: m['opening_balance'] as int,
    creditLimit: m['credit_limit'] as int?,
    archived: (m['archived'] as int) == 1,
    sortOrder: m['sort_order'] as int,
  );

  const Account({
    this.id,
    required this.name,
    required this.kind,
    this.openingBalance = 0,
    this.creditLimit,
    this.archived = false,
    this.sortOrder = 0,
  });

  final int? id;
  final String name;
  final AccountKind kind;

  /// Balance on the day you started tracking, in paise. For a credit card,
  /// enter what you owed as a negative number (or use the form's "owed" field).
  final int openingBalance;

  /// Credit limit in paise, for credit cards only.
  final int? creditLimit;
  final bool archived;
  final int sortOrder;

  Account copyWith({
    int? id,
    String? name,
    AccountKind? kind,
    int? openingBalance,
    int? creditLimit,
    bool? archived,
    int? sortOrder,
  }) => Account(
    id: id ?? this.id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    openingBalance: openingBalance ?? this.openingBalance,
    creditLimit: creditLimit ?? this.creditLimit,
    archived: archived ?? this.archived,
    sortOrder: sortOrder ?? this.sortOrder,
  );

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'name': name,
    'kind': kind.name,
    'opening_balance': openingBalance,
    'credit_limit': creditLimit,
    'archived': archived ? 1 : 0,
    'sort_order': sortOrder,
  };
}
