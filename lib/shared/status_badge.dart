import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

enum StatusTone { success, error, warning, info }

class StatusBadge extends StatelessWidget {
  const StatusBadge({required this.tone, required this.child, super.key});

  final StatusTone tone;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = context.theme.colors.brightness == Brightness.dark;
    final color = switch (tone) {
      StatusTone.success => Color(dark ? 0xFF4ADE80 : 0xFF15803D),
      StatusTone.error => Color(dark ? 0xFFF87171 : 0xFFB91C1C),
      StatusTone.warning => Color(dark ? 0xFFFBBF24 : 0xFFB45309),
      StatusTone.info => Color(dark ? 0xFF60A5FA : 0xFF1D4ED8),
    };
    return FBadge(
      style: .delta(
        decoration: .shapeDelta(
          color: color.withValues(alpha: dark ? 0.16 : 0.1),
        ),
        labelTextStyle: .delta(color: color),
      ),
      child: IconTheme.merge(
        data: IconThemeData(color: color),
        child: child,
      ),
    );
  }
}
