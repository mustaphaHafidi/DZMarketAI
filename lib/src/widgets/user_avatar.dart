import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/utils/avatar_initials.dart';
import 'package:dzmarket/src/utils/public_storage_url_resolver.dart';
import 'package:flutter/material.dart';

class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    this.avatarUrl,
    this.fullName,
    this.email,
    this.radius = 20,
    this.fontSize,
    this.iconSize,
    this.imageRenderMethodForWeb = ImageRenderMethodForWeb.HttpGet,
  });

  final String? avatarUrl;
  final String? fullName;
  final String? email;
  final double radius;
  final double? fontSize;
  final double? iconSize;
  final ImageRenderMethodForWeb imageRenderMethodForWeb;

  static const List<Color> _palette = [
    Color(0xFFCCE4FF),
    Color(0xFFD8F5D0),
    Color(0xFFFFE3C2),
    Color(0xFFF8D3DD),
    Color(0xFFDCD7FF),
    Color(0xFFCDEEE9),
    Color(0xFFFFE5EF),
    Color(0xFFE9E1CC),
  ];

  Color _backgroundColor() {
    final seed = (fullName?.trim().isNotEmpty ?? false)
        ? fullName!.trim()
        : (email?.trim().isNotEmpty ?? false)
        ? email!.trim()
        : '?';
    final index =
        seed.runes.fold<int>(0, (acc, rune) => acc + rune) % _palette.length;
    return _palette[index];
  }

  @override
  Widget build(BuildContext context) {
    final normalizedAvatar = normalizePublicStorageUrl(
      InputSanitizer.safeUrl(avatarUrl),
    );
    final safeAvatar = normalizedAvatar.isEmpty ? null : normalizedAvatar;
    final initials = userInitials(fullName: fullName, email: email);
    final backgroundColor = _backgroundColor();
    final foregroundColor =
        ThemeData.estimateBrightnessForColor(backgroundColor) == Brightness.dark
        ? Colors.white
        : Colors.black87;

    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      backgroundImage: safeAvatar != null
          ? CachedNetworkImageProvider(
              safeAvatar,
              imageRenderMethodForWeb: imageRenderMethodForWeb,
            )
          : null,
      child: safeAvatar == null
          ? (initials == '?'
                ? Icon(Icons.person, size: iconSize ?? radius * 0.95)
                : Text(
                    initials,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: fontSize ?? radius * 0.72,
                      color: foregroundColor,
                    ),
                  ))
          : null,
    );
  }
}
