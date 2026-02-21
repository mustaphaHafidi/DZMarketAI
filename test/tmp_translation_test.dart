import 'package:dzmarket/src/services/translation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('translation service loads key', () async {
    await TranslationService.instance.load();
    final fr = TranslationService.instance.translate('fr', 'listing.add.title_label');
    final ar = TranslationService.instance.translate('ar', 'listing.add.title_label');
    // ignore: avoid_print
    print('FR=' + (fr ?? 'null'));
    // ignore: avoid_print
    print('AR=' + (ar ?? 'null'));
    expect(fr, isNotNull);
    expect(ar, isNotNull);
  });
}
