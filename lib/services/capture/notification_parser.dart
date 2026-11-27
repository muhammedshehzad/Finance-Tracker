/// Reads a payment out of a notification from a UPI app or a bank SMS.
///
/// Pure Dart, so every message shape below is unit tested. Anything that is
/// not clearly a completed payment (OTPs, requests, reminders, failures,
/// offers) returns null and is never shown.
library;

/// Whether money left or reached the account.
enum PaymentDirection { debit, credit }

/// A completed payment read from one notification.
class ParsedPayment {
  const ParsedPayment({
    required this.direction,
    required this.amount,
    this.counterparty,
    this.upiRef,
    this.accountHint,
  });

  final PaymentDirection direction;

  /// Paise.
  final int amount;

  /// Who the money went to or came from, when the message names them.
  final String? counterparty;
  final String? upiRef;

  /// Last digits of the bank account or card, e.g. "1234".
  final String? accountHint;
}

/// Known sources. SMS apps are off by default; see the capture settings.
class PaymentSource {
  const PaymentSource(this.package, this.label, {this.sms = false, this.onByDefault = true});
  final String package;
  final String label;
  final bool sms;
  final bool onByDefault;

  static const all = [
    PaymentSource('com.google.android.apps.nbu.paisa.user', 'Google Pay'),
    PaymentSource('com.phonepe.app', 'PhonePe'),
    PaymentSource('net.one97.paytm', 'Paytm'),
    PaymentSource('in.org.npci.upiapp', 'BHIM'),
    PaymentSource('in.amazon.mShop.android.shopping', 'Amazon Pay', onByDefault: false),
    PaymentSource('com.google.android.apps.messaging', 'Google Messages (bank SMS)', sms: true, onByDefault: false),
    PaymentSource('com.samsung.android.messaging', 'Samsung Messages (bank SMS)', sms: true, onByDefault: false),
    PaymentSource('com.android.mms', 'Messages (bank SMS)', sms: true, onByDefault: false),
  ];

  static PaymentSource? byPackage(String package) => all.where((s) => s.package == package).firstOrNull;
}

/// Reads a [ParsedPayment] from a notification's title and text.
class NotificationParser {
  const NotificationParser();

  static final _amount = RegExp(r'(?:₹|rs\.?|inr)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)', caseSensitive: false);

  /// SBI writes "debited by 90.0" with no currency sign. Accepted for bank
  /// SMS only.
  static final _bareAmount = RegExp(
    r'(?:debited|credited)\s+(?:by|with|for)\s+([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
    caseSensitive: false,
  );

  static final _ignore = RegExp(
    r'\botp\b|one[- ]time password|verification code|'
    r'request(?:ed|ing)?\b|collect request|asking for|'
    r'\bdue\b|reminder|will be (?:debited|deducted|auto)|scheduled|upcoming|mandate (?:created|set)|autopay (?:set|registered)|'
    r'\bfailed\b|declined|unsuccessful|could not|reversed|pending|'
    r'cashback|offer|win |won |reward|coupon|scratch card|'
    r'balance is|avl bal is|available balance is|minimum amount|statement',
    caseSensitive: false,
  );

  /// Canara and some other banks write only "Dr." or "Cr." beside the
  /// amount, and Axis starts with "Debit INR". A bare "credit" is left out,
  /// since "credit card" says nothing about which way money went.
  static final _credit = RegExp(
    r'paid you|received|credited|deposited|refund(?:ed)?|added to your|sent you|money in|'
    r'\bcr\b\.?|\bcredit\s+(?:of\s+)?(?:₹|rs\.?|inr)',
    caseSensitive: false,
  );
  static final _debit = RegExp(
    r'\bpaid\b|\bsent\b|debited|spent|withdrawn|deducted|transferred to|purchase|payment of|money out|'
    r'\bdr\b\.?|\bdebit\s+(?:of\s+)?(?:₹|rs\.?|inr)',
    caseSensitive: false,
  );

  static final _ref = RegExp(
    r'(?:upi\s*ref(?:erence)?(?:\s*no)?|ref(?:erence)?(?:\s*no)?|utr(?:\s*no)?|rrn|txn\s*id|transaction\s*id)[\s.:#-]*([0-9]{10,16})',
    caseSensitive: false,
  );
  static final _bareRef = RegExp(r'(?<![0-9])([0-9]{12})(?![0-9])');

  static final _account = RegExp(
    r'(?:a/?c|acct|account|card)(?:\s*no\.?)?(?:\s*ending(?:\s*with)?)?\s*[*xX.]*\s*([0-9]{3,4})\b',
    caseSensitive: false,
  );

  /// [title] and [text] as shown in the notification. [sms] means the source
  /// is a messaging app, where the bar is higher: a personal text that
  /// mentions "Rs 500" must not look like a payment, so a bank SMS must
  /// also name an account or card, or carry a reference.
  ParsedPayment? parse(String title, String text, {bool sms = false}) {
    final body = '$title. $text'.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (_ignore.hasMatch(body)) return null;

    final amountMatch = _amount.firstMatch(body) ?? (sms ? _bareAmount.firstMatch(body) : null);
    if (amountMatch == null) return null;
    final amount = (double.parse(amountMatch[1]!.replaceAll(',', '')) * 100).round();
    if (amount <= 0) return null;

    final direction = _direction(body);
    if (direction == null) return null;

    final account = _account.firstMatch(body)?[1];
    final ref = _ref.firstMatch(body)?.group(1) ?? (sms ? _bareRef.firstMatch(body)?.group(1) : null);
    if (sms) {
      final bankish = RegExp(r'a/?c|acct|account|card|upi|neft|imps|bank', caseSensitive: false).hasMatch(body);
      if (!bankish || (account == null && ref == null)) return null;
    }

    return ParsedPayment(
      direction: direction,
      amount: amount,
      counterparty: _counterparty(body, direction),
      upiRef: ref,
      accountHint: account,
    );
  }

  /// "Paid you" means money in. Otherwise the first credit or debit word
  /// decides, so "debited from your a/c and credited to rahul@ybl" is a debit.
  PaymentDirection? _direction(String body) {
    if (RegExp(r'paid you|sent you', caseSensitive: false).hasMatch(body)) return PaymentDirection.credit;
    final c = _credit.firstMatch(body)?.start;
    final d = _debit.firstMatch(body)?.start;
    if (c == null && d == null) return null;
    if (c == null) return PaymentDirection.debit;
    if (d == null) return PaymentDirection.credit;
    return c < d ? PaymentDirection.credit : PaymentDirection.debit;
  }

  static final _notAName = RegExp(r'^(?:your|you|a/?c|acct|account|card|bank|self|me)\b', caseSensitive: false);
  static final _masked = RegExp(r'^[*xX0-9 ]+$');

  static final _stop =
      r'(?=\s+(?:on|via|using|through|ref|refno|upi|for|at|in your|from your|is|has|was|with|avl|bal)\b|[.,(;!]|\s+-|$)';

  /// The name after "to"/"at" for a debit or "from"/"by" for a credit,
  /// skipping phrases like "to your a/c" and masked account numbers.
  String? _counterparty(String body, PaymentDirection direction) {
    final patterns = direction == PaymentDirection.debit
        ? [
            RegExp(r'\bto\s+(?:vpa\s+)?(.+?)' + _stop, caseSensitive: false),
            RegExp(r'\bat\s+(.+?)' + _stop, caseSensitive: false),
            RegExp(r'\bfor\s+(.+?)' + _stop, caseSensitive: false),
          ]
        : [
            RegExp(r'\bfrom\s+(?:vpa\s+)?(.+?)' + _stop, caseSensitive: false),
            RegExp(r'\bby\s+(?:vpa\s+)?(.+?)' + _stop, caseSensitive: false),
            RegExp(r'^(.+?)\.\s*(?:paid you|sent you)', caseSensitive: false),
          ];
    for (final p in patterns) {
      for (final m in p.allMatches(body)) {
        final name = m[1]!.trim();
        if (name.isEmpty || name.length > 40) continue;
        if (_notAName.hasMatch(name) || _masked.hasMatch(name)) continue;
        return name;
      }
    }
    return null;
  }
}
