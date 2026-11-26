import 'package:sqflite/sqflite.dart';

import '../models/account.dart';
import '../models/category.dart';

/// Default accounts and categories on first launch. Everything here can be
/// renamed, archived or extended from the app.
Future<void> seedDefaults(DatabaseExecutor db) async {
  final accounts = <Account>[
    const Account(name: 'Cash', kind: AccountKind.cash, sortOrder: 0),
    const Account(name: 'Bank', kind: AccountKind.bank, sortOrder: 1),
    const Account(name: 'Credit card', kind: AccountKind.creditCard, sortOrder: 2),
    const Account(name: 'Lent to others', kind: AccountKind.receivable, sortOrder: 3),
  ];
  for (final a in accounts) {
    await db.insert('accounts', a.toMap());
  }

  var order = 0;
  Category expense(String name, String icon, int color, List<String> keywords) => Category(
    name: name,
    kind: CategoryKind.expense,
    icon: icon,
    color: color,
    keywords: keywords,
    sortOrder: order++,
  );
  Category income(String name, String icon, int color, List<String> keywords) =>
      Category(name: name, kind: CategoryKind.income, icon: icon, color: color, keywords: keywords, sortOrder: order++);

  final categories = <Category>[
    expense('Food', '🍲', 0xFFFFB300, [
      'breakfast',
      'lunch',
      'dinner',
      'tea',
      'chai',
      'coffee',
      'snacks',
      'snack',
      'meal',
      'biryani',
      'juice',
      'restaurant',
      'hotel',
      'swiggy',
      'zomato',
      'bakery',
    ]),
    expense('Groceries', '🛒', 0xFF7CB342, ['grocery', 'groceries', 'vegetables', 'milk', 'supermarket']),
    expense('Transport', '🚌', 0xFF29B6F6, [
      'bus',
      'auto',
      'taxi',
      'cab',
      'uber',
      'ola',
      'rapido',
      'train',
      'metro',
      'petrol',
      'fuel',
      'diesel',
      'parking',
    ]),
    expense('Rent', '🏠', 0xFF66BB6A, ['rent', 'room rent', 'house rent']),
    expense('Mobile settlement', '📱', 0xFFFF7043, ['mobile', 'phone']),
    expense('Bills & recharge', '💡', 0xFF26C6DA, ['recharge', 'electricity', 'wifi', 'internet', 'broadband', 'bill']),
    expense('Akhira (charity)', '🤲', 0xFFFFEE58, [
      'charity',
      'sadaqah',
      'sadaqa',
      'zakat',
      'donation',
      'akhira',
      'masjid',
    ]),
    expense('Google Pay settlement', '💸', 0xFF5C6BC0, ['gpay settlement']),
    expense('Shopping', '🛍️', 0xFFAB47BC, ['shopping', 'clothes', 'dress', 'shoes', 'amazon', 'flipkart']),
    expense('Health', '💊', 0xFFEF5350, ['medicine', 'doctor', 'hospital', 'pharmacy', 'clinic']),
    expense('Family', '👪', 0xFF8D6E63, ['family']),
    expense('Other', '📦', 0xFF9E9E9E, []),
    income('Salary', '💼', 0xFF42A5F5, ['salary', 'payslip']),
    income('Freelance', '🧑‍💻', 0xFF26A69A, ['freelance', 'client', 'project']),
    income('Other income', '💰', 0xFF78909C, ['refund', 'cashback', 'gift', 'bonus']),
  ];
  for (final c in categories) {
    await db.insert('categories', c.toMap());
  }
}
