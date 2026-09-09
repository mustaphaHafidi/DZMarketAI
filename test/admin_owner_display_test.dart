import 'package:dzmarket/src/utils/admin_owner_display.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const ownerId = 'seller-1';

  test('prefers seller full name over the identifier', () {
    expect(
      adminOwnerDisplayName(
        ownerId: ownerId,
        users: const [
          {
            'id': ownerId,
            'full_name': 'Vendeur Test',
            'email': 'seller@example.com',
          },
        ],
      ),
      'Vendeur Test',
    );
  });

  test('falls back to email then identifier', () {
    expect(
      adminOwnerDisplayName(
        ownerId: ownerId,
        users: const [
          {'id': ownerId, 'full_name': '', 'email': 'seller@example.com'},
        ],
      ),
      'seller@example.com',
    );
    expect(adminOwnerDisplayName(ownerId: ownerId, users: const []), ownerId);
  });
}
