import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

/// An icon-only action whose interaction states change only its foreground.
class IconAction extends StatelessWidget {
  const IconAction({
    required this.label,
    required this.icon,
    required this.onPress,
    this.loading = false,
    this.iconSize = 18,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPress;
  final bool loading;
  final double iconSize;

  @override
  Widget build(BuildContext context) => FTappable(
    style: const .delta(
      motion: .delta(bounceTween: FTappableMotion.noBounceTween),
    ),
    focusedOutlineStyle: null,
    semanticsLabel: label,
    semanticsTooltip: label,
    onPress: loading ? null : onPress,
    builder: (context, variants, child) {
      final colors = context.theme.colors;
      final color = variants.contains(FTappableVariant.disabled)
          ? colors.disable(colors.mutedForeground)
          : variants.contains(FTappableVariant.focused)
          ? colors.primary
          : variants.contains(FTappableVariant.hovered) ||
                variants.contains(FTappableVariant.pressed)
          ? colors.foreground
          : colors.mutedForeground;
      return SizedBox.square(
        dimension: 28,
        child: Center(
          child: loading
              ? const FCircularProgress(size: .sm)
              : Icon(icon, size: iconSize, color: color),
        ),
      );
    },
  );
}
