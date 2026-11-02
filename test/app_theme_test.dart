import 'package:azusa/app/theme.dart';
import 'package:azusa/core/settings/settings.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('默认和旧版中性主题使用 Azusa 红，其他已选配色保留', () {
    expect(const AppSettings().themeColor, AppThemeColor.azusa);
    expect(AppSettings.fromJson({}).themeColor, AppThemeColor.azusa);
    expect(
      AppSettings.fromJson({'themeColor': 'neutral'}).themeColor,
      AppThemeColor.azusa,
    );
    expect(
      AppSettings.fromJson({'themeColor': 'blue'}).themeColor,
      AppThemeColor.blue,
    );
    expect(
      AppSettings.fromJson(const AppSettings().toJson()).themeColor,
      AppThemeColor.azusa,
    );
  });

  for (final brightness in Brightness.values) {
    test('Azusa 红在 $brightness 下保持指定色值和白色前景', () {
      final theme = createAppTheme(
        const AppSettings(),
        brightness: brightness,
        touch: false,
      );
      expect(theme.colors.primary, const Color(0xFFD63B40));
      expect(theme.colors.primaryForeground, const Color(0xFFFFFFFF));
    });
  }
}
