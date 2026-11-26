import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/models/account.dart';
import '../data/models/category.dart';
import '../data/models/txn.dart';

/// Writes all transactions to a CSV file that opens in Excel or Sheets.
class CsvExport {
  static final _date = DateFormat('yyyy-MM-dd HH:mm');

  static String build(List<Txn> txns, List<Account> accounts, List<Category> categories) {
    final accountName = {for (final a in accounts) a.id: a.name};
    final categoryName = {for (final c in categories) c.id: c.name};
    final rows = <List<String>>[
      [
        'Date',
        'Type',
        'Amount',
        'Category',
        'Account',
        'To account',
        'Note',
        'Description',
        'Payee',
        'UPI ref',
        'Source',
      ],
      for (final t in txns)
        [
          _date.format(t.date),
          t.type.name,
          (t.amount / 100).toStringAsFixed(2),
          categoryName[t.categoryId] ?? '',
          accountName[t.accountId] ?? '',
          accountName[t.toAccountId] ?? '',
          t.note,
          t.description,
          t.payee ?? '',
          t.upiRef ?? '',
          t.source.name,
        ],
    ];
    return rows.map((r) => r.map(_escape).join(',')).join('\r\n');
  }

  static String _escape(String v) {
    if (v.contains(RegExp(r'[",\r\n]'))) return '"${v.replaceAll('"', '""')}"';
    return v;
  }

  /// Writes [csv] to a temporary file with a byte-order mark, so Excel reads
  /// the ₹ sign and non-English text correctly.
  static Future<File> writeFile(String csv) async {
    final dir = await getTemporaryDirectory();
    final name = 'finance_export_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv';
    return File(p.join(dir.path, name)).writeAsString('﻿$csv');
  }
}
