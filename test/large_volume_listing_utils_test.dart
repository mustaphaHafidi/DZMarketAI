import 'package:dzmarket/src/utils/large_volume_listing_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('matches real large-volume keywords', () {
    expect(
      hasLargeVolumeListingKeywords(['Bureau moderne', 'meuble de bureau']),
      isTrue,
    );
  });

  test('does not classify tablette as table', () {
    expect(
      hasLargeVolumeListingKeywords(['tablette honor', 'bon etat']),
      isFalse,
    );
  });
}
