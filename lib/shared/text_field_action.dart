import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

/// A trailing icon action without a button surface or an exterior focus ring.
class TextFieldAction extends StatelessWidget {
  const TextFieldAction({
    required this.style,
    required this.label,
    required this.icon,
    required this.onPress,
    this.loading = false,
    super.key,
  });

  final FTextFieldStyle style;
  final String label;
  final IconData icon;
  final VoidCallback? onPress;
  final bool loading;

  @override
  Widget build(BuildContext context) => Padding(
    padding: style.obscureButtonPadding,
    child: FTappable(
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
                : Icon(icon, size: 18, color: color),
          ),
        );
      },
    ),
  );
}
