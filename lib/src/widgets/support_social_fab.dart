import 'package:dzmarket/src/services/i18n.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class SupportSocialFab extends StatefulWidget {
  const SupportSocialFab({super.key, this.onOpen});

  final Future<void> Function(Uri uri)? onOpen;

  @override
  State<SupportSocialFab> createState() => _SupportSocialFabState();
}

class _SupportSocialFabState extends State<SupportSocialFab> {
  bool _isOpen = false;

  static final _destinations = <_SocialDestination>[
    _SocialDestination(
      keyName: 'support.contact',
      uri: 'https://m.me/DZMarketpro',
      icon: FontAwesomeIcons.facebookMessenger.data,
      color: Color(0xFF0084FF),
    ),
    _SocialDestination(
      keyName: 'support.facebook',
      uri: 'https://www.facebook.com/DZMarketpro',
      icon: Icons.facebook_rounded,
      color: Color(0xFF1877F2),
    ),
    _SocialDestination(
      keyName: 'support.instagram',
      uri: 'https://www.instagram.com/dzmarketpro/',
      icon: FontAwesomeIcons.instagram.data,
      color: Color(0xFFC13584),
    ),
    _SocialDestination(
      keyName: 'support.youtube',
      uri: 'https://www.youtube.com/@dzmarketpro',
      icon: Icons.play_arrow_rounded,
      color: Color(0xFFFF0000),
    ),
  ];

  Future<void> _open(_SocialDestination destination) async {
    setState(() => _isOpen = false);
    final uri = Uri.parse(destination.uri);
    if (widget.onOpen != null) {
      await widget.onOpen!(uri);
      return;
    }
    await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = L10n.tr(context, 'support.title');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isOpen)
          ..._destinations.reversed.map(
            (destination) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Tooltip(
                message: L10n.tr(context, destination.keyName),
                child: Semantics(
                  button: true,
                  label: L10n.tr(context, destination.keyName),
                  child: _CircleButton(
                    color: destination.color,
                    icon: destination.icon,
                    onPressed: () => _open(destination),
                  ),
                ),
              ),
            ),
          ),
        Tooltip(
          message: title,
          child: Semantics(
            button: true,
            label: title,
            expanded: _isOpen,
            child: _CircleButton(
              color: Theme.of(context).colorScheme.primary,
              icon: _isOpen ? Icons.close_rounded : Icons.support_agent_rounded,
              onPressed: () => setState(() => _isOpen = !_isOpen),
            ),
          ),
        ),
      ],
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.color,
    required this.icon,
    required this.onPressed,
  });

  final Color color;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      elevation: 3,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

class _SocialDestination {
  const _SocialDestination({
    required this.keyName,
    required this.uri,
    required this.icon,
    required this.color,
  });

  final String keyName;
  final String uri;
  final IconData icon;
  final Color color;
}
