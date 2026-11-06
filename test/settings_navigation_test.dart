import 'package:azusa/features/settings/settings_tab.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('设置 Tab 标识和地址稳定，缺失及非法标识回退常规', () {
    for (final tab in SettingsTab.values) {
      expect(SettingsTab.fromParameter(tab.name), tab);
      expect(Uri.parse(tab.location).queryParameters['tab'], tab.name);
    }
    expect(SettingsTab.fromParameter(null), SettingsTab.general);
    expect(SettingsTab.fromParameter('invalid'), SettingsTab.general);
  });
}
