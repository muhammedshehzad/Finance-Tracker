import 'dart:io';

import 'package:finance_tracker/data/db/app_database.dart';
import 'package:finance_tracker/data/finance_repository.dart';
import 'package:finance_tracker/data/models/account.dart';
import 'package:finance_tracker/data/models/captured_payment.dart';
import 'package:finance_tracker/data/models/category.dart';
import 'package:finance_tracker/data/models/txn.dart';
import 'package:finance_tracker/services/capture/capture_channel.dart';
import 'package:finance_tracker/services/capture/capture_service.dart';
import 'package:finance_tracker/services/capture/notification_parser.dart';
import 'package:finance_tracker/state/providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeChannel extends CaptureChannel {
  FakeChannel(this.queue);
  final List<RawNotification> queue;
  @override
  bool get supported => true;
  @override
  Future<List<RawNotification>> drain() async {
    final out = List.of(queue);
    queue.clear();
    return out;
  }
}

const gpay = 'com.google.android.apps.nbu.paisa.user';
const sms = 'com.google.android.apps.messaging';

RawNotification n(String package, String title, String text, DateTime at, [String? key]) =>
    RawNotification(key: key ?? '$package|$title|$text|$at', package: package, title: title, text: text, postedAt: at);

void main() {
  sqfliteFfiInit();
  late FinanceRepository repo;
  late Directory dir;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('capture');
    repo = FinanceRepository(await AppDatabase.open(factory: databaseFactoryFfi, path: '${dir.path}/t.db'));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('keeps payments, drops noise, stores a repost once and pairs app + SMS', () async {
    final t0 = DateTime(2026, 11, 26, 13, 0);
    final queue = [
      n(gpay, '₹450 paid to Swiggy', 'Paid using HDFC Bank', t0, 'k1'),
      n(gpay, '₹450 paid to Swiggy', 'Paid using HDFC Bank', t0, 'k1'),
      n(
        sms,
        'AX-HDFCBK',
        'Rs.450.00 debited from A/c XX1234 on 26-11-26 to VPA swiggy@icici (UPI Ref No 533412987654).',
        t0.add(const Duration(minutes: 1)),
      ),
      n(sms, 'AX-HDFCBK', '482913 is the OTP for your txn of Rs 2,000. Do not share.', t0),
      n(gpay, 'Arif Khan', 'Paid you ₹2,000', t0.add(const Duration(hours: 1))),
    ];
    final service = CaptureService(repo, channel: FakeChannel(queue));

    expect(await service.sync(), 3);
    final pending = await repo.capturedPayments(status: CaptureStatus.pending);
    expect(pending, hasLength(3));
    final bankSms = pending.singleWhere((c) => c.package == sms);
    final app = pending.singleWhere((c) => c.package == gpay && c.amount == 45000);
    expect(bankSms.possibleDuplicateOf, app.id);
    expect(bankSms.accountHint, '1234');
    expect(pending.singleWhere((c) => c.direction == PaymentDirection.credit).counterparty, 'Arif Khan');

    expect(await service.sync(), 0, reason: 'queue drained');
  });

  test('a capture whose UPI reference is already recorded is set aside', () async {
    final accounts = await repo.accounts();
    final bank = accounts.firstWhere((a) => a.kind == AccountKind.bank).id!;
    final food = (await repo.categories(kind: CategoryKind.expense)).first.id!;
    await repo.saveTxn(
      Txn(
        type: TxnType.expense,
        amount: 9000,
        date: DateTime(2026, 11, 26),
        accountId: bank,
        categoryId: food,
        upiRef: '533498765432',
      ),
    );

    final service = CaptureService(
      repo,
      channel: FakeChannel([
        n(
          sms,
          'VM-SBIUPI',
          'Dear UPI user A/C X5678 debited by 90.0 on date 26Nov26 trf to ZOMATO Refno 533498765432.',
          DateTime(2026, 11, 26, 9),
        ),
      ]),
    );
    expect(await service.sync(), 0);
    expect((await repo.capturedPayments()).single.status, CaptureStatus.duplicate);
  });

  test('draft guesses the category from the payee and uses the bank account', () async {
    final service = CaptureService(
      repo,
      channel: FakeChannel([n(gpay, '₹120 paid to Chai Point', 'lunch tea', DateTime(2026, 11, 26, 16))]),
    );
    await service.sync();
    final c = (await repo.capturedPayments()).single;
    final l = Lookups(await repo.accounts(includeArchived: true), await repo.categories(includeArchived: true));
    final d = draftFromCapture(c, l);
    expect(d.type, TxnType.expense);
    expect(d.amount, 12000);
    expect(d.note, 'Chai Point');
    expect(d.source, TxnSource.notification);
    expect(l.accountById[d.accountId]!.kind, AccountKind.bank);
    expect(l.categoryById[d.categoryId]?.name, 'Food');
  });

  test('an install on schema 1 gains the newer tables on upgrade', () async {
    final path = '${dir.path}/old.db';
    final first = await AppDatabase.open(factory: databaseFactoryFfi, path: path);
    // Everything added after schema 1.
    await first.db.execute('DROP TABLE captured_payments');
    await first.db.execute('DROP TABLE settings');
    await first.db.setVersion(1);
    await first.close();

    final upgraded = FinanceRepository(await AppDatabase.open(factory: databaseFactoryFfi, path: path));
    expect(await upgraded.capturedPayments(), isEmpty);
    expect(await upgraded.setting('app_lock'), isNull);
    expect(await upgraded.accounts(), isNotEmpty, reason: 'existing data kept');
  });
}
