import 'package:flutter/material.dart';

class WebFrame extends StatelessWidget {
  const WebFrame({
    super.key,
    required this.child,
    this.maxWidth = 1400,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.applyMediaQuery = true,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;
  final bool applyMediaQuery;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final media = MediaQuery.of(context);
        final availableWidth = constraints.maxWidth;
        if (availableWidth <= maxWidth) {
          return child;
        }
        final framed = Align(
          alignment: Alignment.topCenter,
          child: SizedBox(width: maxWidth, child: child),
        );
        final wrapped = applyMediaQuery
            ? MediaQuery(
                data: media.copyWith(size: Size(maxWidth, media.size.height)),
                child: framed,
              )
            : framed;
        return DecoratedBox(
          decoration: const BoxDecoration(
            color: Color(0xFFF2FAF3),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF2FAF3), Color(0xFFEAF6EC), Color(0xFFF7FBF8)],
            ),
          ),
          child: Padding(
            padding: padding,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: media.size.height),
              child: wrapped,
            ),
          ),
        );
      },
    );
  }
}
