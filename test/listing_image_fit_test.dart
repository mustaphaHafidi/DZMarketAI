import 'package:dzmarket/src/utils/listing_image_fit.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps a vehicle image complete in fixed-ratio surfaces', () {
    expect(listingImageFit('vehicles-cars'), BoxFit.contain);
    expect(listingImageFit('vehicles-trucks'), BoxFit.contain);
  });

  test('preserves the existing crop behavior for other categories', () {
    expect(listingImageFit('electronics'), BoxFit.cover);
    expect(listingImageFit(null), BoxFit.cover);
  });
}
