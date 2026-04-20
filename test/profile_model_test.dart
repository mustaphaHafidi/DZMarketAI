import 'package:dzmarket/src/models/profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Profile.fromJson normalizes legacy avatar URLs', () {
    final profile = Profile.fromJson({
      'id': 'user-1',
      'email': 'user@example.com',
      'avatar_url':
          'https://maumwzbvzbcamvlivqpe.supabase.co/storage/v1/object/public/avatars/user-1/demo.webp',
      'role': 'buyer',
      'status': 'active',
    });

    expect(
      profile.avatarUrl,
      'https://api.dzmarket.pro/storage/v1/object/public/avatars/user-1/demo.webp',
    );
  });
}
