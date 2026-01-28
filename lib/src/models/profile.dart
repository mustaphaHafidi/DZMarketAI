enum UserRole { buyer, seller, admin }

class Profile {
  const Profile({
    required this.id,
    required this.email,
    this.fullName,
    this.avatarUrl,
    this.phone,
    this.wilaya,
    this.daira,
    this.locationLat,
    this.locationLng,
    this.bio,
    this.lang,
    this.isPublic = true,
    this.isSeller = false,
    this.preferences = const {},
    required this.role,
  });

  final String id;
  final String email;
  final String? fullName;
  final String? avatarUrl;
  final String? phone;
  final String? wilaya;
  final String? daira;
  final double? locationLat;
  final double? locationLng;
  final String? bio;
  final String? lang;
  final bool isPublic;
  final bool isSeller;
  final Map<String, dynamic> preferences;
  final UserRole role;

  factory Profile.fromJson(Map<String, dynamic> json) {
    final roleString = (json['role'] as String?) ?? 'buyer';
    return Profile(
      id: json['id'] as String,
      email: json['email'] as String? ?? '',
      fullName: json['full_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      phone: json['phone'] as String?,
      wilaya: json['wilaya'] as String?,
      daira: json['daira'] as String?,
      locationLat: (json['location_lat'] as num?)?.toDouble(),
      locationLng: (json['location_lng'] as num?)?.toDouble(),
      bio: json['bio'] as String?,
      lang: json['lang'] as String?,
      isPublic: json['is_public'] as bool? ?? true,
      isSeller: json['is_seller'] as bool? ?? false,
      preferences: (json['preferences'] as Map?)?.cast<String, dynamic>() ?? const {},
      role: _roleFromString(roleString),
    );
  }

  static UserRole _roleFromString(String value) {
    switch (value) {
      case 'seller':
        return UserRole.seller;
      case 'admin':
        return UserRole.admin;
      default:
        return UserRole.buyer;
    }
  }
}
