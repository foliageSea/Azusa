import 'package:flutter/widgets.dart';

/// Resolves a saved font size tier (0.8 small, 1.0 standard, 1.2 large) into
/// the percentage for the current device pixel ratio.
double resolveFontScale(double tier, double devicePixelRatio) {
  final index = tier < 0.9 ? 0 : (tier > 1.1 ? 2 : 1);
  final scales = switch (devicePixelRatio) {
    <= 1.5 => const [0.65, 0.8, 1.0],
    < 2.5 => const [0.85, 1.0, 1.2],
    _ => const [0.57, 0.72, 0.92],
  };
  return scales[index];
}

/// Applies the app preference without replacing the system's scaling curve.
final class AppTextScaler extends TextScaler {
  const AppTextScaler(this.systemScaler, this.fontScale)
    : assert(fontScale > 0 && fontScale < double.infinity);

  final TextScaler systemScaler;
  final double fontScale;

  @override
  double scale(double fontSize) => systemScaler.scale(fontSize) * fontScale;

  // Required by TextScaler for compatibility with legacy consumers.
  @override
  double get textScaleFactor => scale(14) / 14;

  @override
  bool operator ==(Object other) =>
      other is AppTextScaler &&
      other.systemScaler == systemScaler &&
      other.fontScale == fontScale;

  @override
  int get hashCode => Object.hash(systemScaler, fontScale);
}
