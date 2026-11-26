import '../data/models/account.dart';
import '../data/models/category.dart';
import '../data/models/txn.dart';
import 'category_matcher.dart';

/// One entry understood from speech, waiting for the user to confirm.
class VoiceDraft {
  const VoiceDraft({
    required this.type,
    required this.amountPaise,
    this.categoryId,
    this.note = '',
    this.accountHint,
    this.toAccountHint,
    this.payee,
    required this.phrase,
  });

  final TxnType type;
  final int amountPaise;
  final int? categoryId;
  final String note;

  /// Which kind of account the phrase pointed to ("by cash", "on card").
  final AccountKind? accountHint;

  /// For transfers: where the money went (credit card bill, money lent).
  final AccountKind? toAccountHint;
  final String? payee;

  /// The part of the transcript this entry came from.
  final String phrase;
}

/// Turns phrases like "paid 90 for lunch and 30 for tea by cash",
/// "rent 2500", "received 25,000 salary" or "lent 500 to Ameen" into drafts.
///
/// Rule based and offline. It never saves anything itself: the app shows a
/// confirm sheet first.
class VoiceParser {
  VoiceParser(List<Category> categories) : _matcher = CategoryMatcher(categories);

  final CategoryMatcher _matcher;

  List<VoiceDraft> parse(String transcript) {
    final normalized = normalize(transcript);
    if (normalized.isEmpty) return const [];
    final sharedAccount = _accountHint(normalized);
    final drafts = <VoiceDraft>[];
    for (final segment in _segments(normalized)) {
      final d = _parseSegment(segment, sharedAccount);
      if (d != null) drafts.add(d);
    }
    return drafts;
  }

  static const _units = {
    'zero': 0,
    'one': 1,
    'two': 2,
    'three': 3,
    'four': 4,
    'five': 5,
    'six': 6,
    'seven': 7,
    'eight': 8,
    'nine': 9,
    'ten': 10,
    'eleven': 11,
    'twelve': 12,
    'thirteen': 13,
    'fourteen': 14,
    'fifteen': 15,
    'sixteen': 16,
    'seventeen': 17,
    'eighteen': 18,
    'nineteen': 19,
    'twenty': 20,
    'thirty': 30,
    'forty': 40,
    'fifty': 50,
    'sixty': 60,
    'seventy': 70,
    'eighty': 80,
    'ninety': 90,
  };
  static const _scales = {
    'hundred': 100,
    'thousand': 1000,
    'lakh': 100000,
    'lakhs': 100000,
    'lac': 100000,
    'crore': 10000000,
  };

  /// Lower-cases, strips currency words and turns spoken numbers into digits:
  /// "2,500" and "1,00,000" lose their commas, "2k" and "1.5 lakh" are
  /// expanded, and "two hundred and fifty" becomes 250.
  static String normalize(String input) {
    var t = input.toLowerCase().replaceAll('₹', ' ').replaceAll(RegExp(r'[!?;]'), ' ');
    t = t.replaceAllMapped(RegExp(r'(\d),(\d{2,3})\b'), (m) => '${m[1]}${m[2]}');
    t = t.replaceAllMapped(RegExp(r'(\d),(\d{2,3})\b'), (m) => '${m[1]}${m[2]}');
    t = t.replaceAllMapped(RegExp(r'\b(\d+(?:\.\d+)?)\s?k\b'), (m) {
      return (double.parse(m[1]!) * 1000).round().toString();
    });
    t = t.replaceAllMapped(RegExp(r'\b(\d+(?:\.\d+)?)\s+(hundred|thousand|lakhs?|lac|crore)\b'), (m) {
      return (double.parse(m[1]!) * _scales[m[2]!]!).round().toString();
    });
    t = _wordsToDigits(t);
    t = t.replaceAll(RegExp(r'\b(rupees?|rs\.?|inr|bucks)\b'), ' ');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _wordsToDigits(String text) {
    final tokens = text.split(' ');
    final out = <String>[];
    var i = 0;
    while (i < tokens.length) {
      if (!_isNumberWord(tokens[i])) {
        out.add(tokens[i]);
        i++;
        continue;
      }
      var total = 0;
      var current = 0;
      var j = i;
      while (j < tokens.length) {
        final w = tokens[j];
        if (_units.containsKey(w)) {
          current += _units[w]!;
        } else if (w == 'hundred') {
          current = (current == 0 ? 1 : current) * 100;
        } else if (_scales.containsKey(w)) {
          total += (current == 0 ? 1 : current) * _scales[w]!;
          current = 0;
        } else if (w != 'and' || j == i || j + 1 >= tokens.length || !_isNumberWord(tokens[j + 1])) {
          break;
        }
        j++;
      }
      out.add('${total + current}');
      i = j;
    }
    return out.join(' ');
  }

  static bool _isNumberWord(String w) => _units.containsKey(w) || _scales.containsKey(w);

  static final _amountPattern = RegExp(r'\b\d+(?:\.\d{1,2})?\b');

  /// Splits "lunch 90 and tea 30" into two phrases, but keeps
  /// "tea and snacks 50" as one because only one part has an amount. Words
  /// without an amount ("by cash") join a neighbouring phrase.
  List<String> _segments(String text) {
    final parts = text.split(RegExp(r'\s*(?:,|\band\b|\bthen\b|\balso\b|\.)\s*'));
    final segments = <String>[];
    var pending = '';
    for (final part in parts) {
      if (part.trim().isEmpty) continue;
      final combined = pending.isEmpty ? part : '$pending and $part';
      if (_amountPattern.hasMatch(part)) {
        if (pending.isNotEmpty && !_amountPattern.hasMatch(pending)) {
          segments.add(combined);
        } else {
          if (pending.isNotEmpty) segments.add(pending);
          segments.add(part);
        }
        pending = '';
      } else {
        if (segments.isNotEmpty && pending.isEmpty) {
          segments[segments.length - 1] = '${segments.last} $part';
        } else {
          pending = combined;
        }
      }
    }
    if (pending.isNotEmpty) {
      if (segments.isEmpty) {
        segments.add(pending);
      } else {
        segments[segments.length - 1] = '${segments.last} $pending';
      }
    }
    return segments;
  }

  static final _incomeWords = RegExp(r'\b(received|receive|got|credited|salary|earned|income|refund|cashback)\b');
  static final _lentWords = RegExp(r'\b(lent|lend|loaned|gave loan|given as loan)\b');
  static final _repaidWords = RegExp(r'\b(repaid|returned|paid back|got back)\b');
  static final _cardBillWords = RegExp(r'\b(credit card bill|card bill|card payment|paid (?:the )?card)\b');

  VoiceDraft? _parseSegment(String segment, AccountKind? sharedAccount) {
    final amountMatch = _amountPattern.firstMatch(segment);
    if (amountMatch == null) return null;
    final amount = (double.parse(amountMatch.group(0)!) * 100).round();
    if (amount <= 0) return null;

    final account = _accountHint(segment) ?? sharedAccount;

    if (_cardBillWords.hasMatch(segment)) {
      return VoiceDraft(
        type: TxnType.transfer,
        amountPaise: amount,
        note: 'Credit card bill',
        accountHint: AccountKind.bank,
        toAccountHint: AccountKind.creditCard,
        phrase: segment,
      );
    }
    if (_repaidWords.hasMatch(segment)) {
      final who = _personAfter(segment, RegExp(r'\b(?:from|by)\s+'));
      return VoiceDraft(
        type: TxnType.transfer,
        amountPaise: amount,
        note: who == null ? 'Loan repaid' : 'Repaid by $who',
        accountHint: AccountKind.receivable,
        toAccountHint: account == AccountKind.cash ? AccountKind.cash : AccountKind.bank,
        payee: who,
        phrase: segment,
      );
    }
    if (_lentWords.hasMatch(segment)) {
      final who = _personAfter(segment, RegExp(r'\bto\s+'));
      return VoiceDraft(
        type: TxnType.transfer,
        amountPaise: amount,
        note: who == null ? 'Lent' : 'Lent to $who',
        accountHint: account == AccountKind.cash ? AccountKind.cash : AccountKind.bank,
        toAccountHint: AccountKind.receivable,
        payee: who,
        phrase: segment,
      );
    }

    final isIncome = _incomeWords.hasMatch(segment);
    final kind = isIncome ? CategoryKind.income : CategoryKind.expense;
    final category = _matcher.match(segment, kind) ?? _matcher.fallback(kind);
    return VoiceDraft(
      type: isIncome ? TxnType.income : TxnType.expense,
      amountPaise: amount,
      categoryId: category?.id,
      note: _noteFrom(segment),
      accountHint: account,
      phrase: segment,
    );
  }

  AccountKind? _accountHint(String text) {
    if (RegExp(r'\b(credit card|by card|on card|with card|on the card)\b').hasMatch(text) &&
        !_cardBillWords.hasMatch(text)) {
      return AccountKind.creditCard;
    }
    if (RegExp(r'\b(cash|in hand)\b').hasMatch(text)) return AccountKind.cash;
    if (RegExp(r'\b(gpay|g pay|google pay|phonepe|phone pe|paytm|upi|bank|account|online)\b').hasMatch(text)) {
      return AccountKind.bank;
    }
    return null;
  }

  String? _personAfter(String text, RegExp marker) {
    final m = marker.firstMatch(text);
    if (m == null) return null;
    final rest = text.substring(m.end).replaceAll(_amountPattern, '').trim();
    final words = rest
        .split(' ')
        .where((w) => w.isNotEmpty && !_fillers.contains(w) && !_accountWords.contains(w))
        .take(3)
        .toList();
    if (words.isEmpty) return null;
    return _titleCase(words.join(' '));
  }

  static const _fillers = {
    'i',
    'have',
    'had',
    'paid',
    'pay',
    'spent',
    'spend',
    'for',
    'on',
    'the',
    'a',
    'an',
    'of',
    'to',
    'at',
    'today',
    'yesterday',
    'just',
    'my',
    'me',
    'it',
    'was',
    'is',
    'received',
    'got',
    'credited',
    'with',
    'by',
    'from',
    'some',
    'bought',
    'buy',
    'add',
    'expense',
    'record',
    'note',
    'amount',
    'please',
    'and',
    'in',
  };
  static const _accountWords = {
    'cash',
    'card',
    'credit',
    'gpay',
    'google',
    'pay',
    'phonepe',
    'paytm',
    'upi',
    'bank',
    'account',
    'online',
    'hand',
  };

  String _noteFrom(String segment) {
    final words = segment
        .replaceAll(_amountPattern, ' ')
        .split(' ')
        .where((w) => w.isNotEmpty && !_fillers.contains(w) && !_accountWords.contains(w))
        .toList();
    return _titleCase(words.join(' '));
  }

  static String _titleCase(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}
