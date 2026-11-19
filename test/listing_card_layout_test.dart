import 'package:dzmarket/src/utils/listing_card_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compact two-column cards never render delivery badges', () {
    expect(
      shouldShowListingCardBadges(
        isCompactCard: true,
        hasBadges: true,
        contentHeight: 120,
      ),
      isFalse,
    );
  });

  test('larger cards render badges only with enough content height', () {
    expect(
      shouldShowListingCardBadges(
        isCompactCard: false,
        hasBadges: true,
        contentHeight: 81,
      ),
      isFalse,
    );
    expect(
      shouldShowListingCardBadges(
        isCompactCard: false,
        hasBadges: true,
        contentHeight: 82,
      ),
      isTrue,
    );
  });
}
