import '../../data/finance_repository.dart';
import '../../data/models/captured_payment.dart';
import 'capture_channel.dart';
import 'notification_parser.dart';

/// Collects notifications from the listener, keeps the ones that are
/// payments, and sets aside those already recorded.
class CaptureService {
  CaptureService(this._repo, {this._channel = const CaptureChannel(), this._parser = const NotificationParser()});

  final FinanceRepository _repo;
  final CaptureChannel _channel;
  final NotificationParser _parser;

  /// How close two captures of the same amount must be to look like one
  /// payment seen twice (app notification and bank SMS).
  static const pairWindow = Duration(minutes: 10);

  /// Returns how many new payments are waiting for review.
  Future<int> sync() async {
    final raw = await _channel.drain();
    if (raw.isEmpty) return 0;
    return store(raw);
  }

  Future<int> store(List<RawNotification> raw) async {
    var added = 0;
    for (final n in raw) {
      final source = PaymentSource.byPackage(n.package);
      final parsed = _parser.parse(n.title, n.text, sms: source?.sms ?? false);
      if (parsed == null) continue;

      var status = CaptureStatus.pending;
      if (parsed.upiRef != null && await _repo.findByUpiRef(parsed.upiRef!) != null) {
        status = CaptureStatus.duplicate;
      }

      final recent = await _repo.capturedPayments(since: n.postedAt.subtract(pairWindow));
      int? pairedWith;
      for (final c in recent) {
        if (c.amount != parsed.amount || c.direction != parsed.direction) continue;
        if (c.postedAt.difference(n.postedAt).abs() > pairWindow) continue;
        if (parsed.upiRef != null && c.upiRef == parsed.upiRef) {
          status = CaptureStatus.duplicate;
          pairedWith = c.id;
          break;
        }
        if (c.package != n.package) pairedWith ??= c.id;
      }

      final id = await _repo.insertCaptured(
        CapturedPayment(
          key: n.key,
          package: n.package,
          postedAt: n.postedAt,
          direction: parsed.direction,
          amount: parsed.amount,
          title: n.title,
          text: n.text,
          counterparty: parsed.counterparty,
          upiRef: parsed.upiRef,
          accountHint: parsed.accountHint,
          status: status,
          possibleDuplicateOf: pairedWith,
        ),
      );
      if (id != null && status == CaptureStatus.pending) added++;
    }
    await _repo.pruneCaptured();
    return added;
  }
}
