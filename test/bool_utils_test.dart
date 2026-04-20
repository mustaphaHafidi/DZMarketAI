import 'package:dzmarket/src/utils/bool_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('isTruthyFlag accepts common boolean representations', () {
    expect(isTruthyFlag(true), isTrue);
    expect(isTruthyFlag('true'), isTrue);
    expect(isTruthyFlag('1'), isTrue);
    expect(isTruthyFlag('t'), isTrue);
    expect(isTruthyFlag('yes'), isTrue);
  });

  test('isTruthyFlag rejects null and falsey values', () {
    expect(isTruthyFlag(false), isFalse);
    expect(isTruthyFlag('false'), isFalse);
    expect(isTruthyFlag('0'), isFalse);
    expect(isTruthyFlag(null), isFalse);
  });
}
