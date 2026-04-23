import 'package:dzmarket/src/utils/text_encoding_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('repairMojibake leaves healthy text untouched', () {
    expect(repairMojibake('Offre refusee'), 'Offre refusee');
  });

  test('repairMojibake repairs common UTF-8/Latin-1 corruption', () {
    expect(repairMojibake('RefusÃ©e'), 'Refusée');
    expect(repairMojibake('Lien copiÃ©'), 'Lien copié');
  });
}
