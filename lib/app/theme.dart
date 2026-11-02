import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../core/settings/settings.dart';

const azusaPrimaryColor = Color(0xFFD63B40);

extension AppThemePalette on AppThemeColor {
  Color primary(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return switch (this) {
      AppThemeColor.azusa => azusaPrimaryColor,
      AppThemeColor.neutral =>
        dark ? FColors.neutralDark.primary : FColors.neutralLight.primary,
      AppThemeColor.blue => Color(dark ? 0xff60a5fa : 0xff1d4ed8),
      AppThemeColor.green => Color(dark ? 0xff4ade80 : 0xff15803d),
      AppThemeColor.violet => Color(dark ? 0xffa78bfa : 0xff6d28d9),
      AppThemeColor.orange => Color(dark ? 0xfffb923c : 0xffc2410c),
      AppThemeColor.rose => Color(dark ? 0xfffb7185 : 0xffbe123c),
    };
  }
}

const appFontFamily = 'MiSans';

FThemeData createAppTheme(
  AppSettings settings, {
  required Brightness brightness,
  required bool touch,
}) {
  final dark = brightness == Brightness.dark;
  final neutral = dark ? FColors.neutralDark : FColors.neutralLight;
  final colors = neutral.copyWith(
    primary: settings.themeColor.primary(brightness),
    primaryForeground: settings.themeColor == AppThemeColor.azusa
        ? const Color(0xFFFFFFFF)
        : neutral.primaryForeground,
  );
  final typeface = FTypeface.inherit(
    colors: colors,
    touch: touch,
    fontFamily: appFontFamily,
  );
  final typography = FTypography(display: typeface, body: typeface);
  final radii = const FBorderRadius().scale(settings.radiusScale);
  final style =
      FStyle.inherit(
        colors: colors,
        typography: typography,
        touch: touch,
      ).copyWith(
        borderRadius: radii,
        focusedOutlineStyle: FFocusedOutlineStyle(
          color: colors.primary,
          borderRadius: radii.md,
        ),
      );
  // Rebuild component styles from tokens so buttons, fields and overlays update together.
  return FThemeData(
    colors: colors,
    typography: typography,
    style: style,
    touch: touch,
  );
}

final appThemesProvider = Provider((ref) {
  final (color, radius) = ref.watch(
    settingsProvider.select((s) => (s.themeColor, s.radiusScale)),
  );
  final settings = AppSettings(themeColor: color, radiusScale: radius);
  final touch =
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  return (
    light: createAppTheme(settings, brightness: Brightness.light, touch: touch),
    dark: createAppTheme(settings, brightness: Brightness.dark, touch: touch),
  );
});
