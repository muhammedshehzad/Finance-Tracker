import 'package:finance_tracker/core/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats with Indian lakh grouping', () {
    expect(formatMoney(24205900), '₹2,42,059');
    expect(formatMoney(4692728), '₹46,927.28');
    expect(formatMoney(-1474228), '-₹14,742.28');
    expect(formatMoney(9000, symbol: false), '90');
  });

  test('parses user input', () {
    expect(parseMoney('1,250.5'), 125050);
    expect(parseMoney('₹90'), 9000);
    expect(parseMoney('0'), isNull);
    expect(parseMoney('abc'), isNull);
    expect(parseMoney('1.234'), isNull);
  });

  test('round trips to an editable string', () {
    expect(paiseToInput(125050), '1250.50');
    expect(paiseToInput(9000), '90');
  });
}
