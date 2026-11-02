import 'package:azusa/core/settings/naming_language.dart';
import 'package:azusa/core/settings/settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('命名语言默认简体中文，兼容旧配置和无效值', () {
    expect(
      const AppSettings().namingLanguage,
      NamingLanguage.simplifiedChinese,
    );
    for (final json in <Map<String, dynamic>>[
      {},
      {'language': 'en'},
      {'namingLanguage': 'invalid'},
      {'namingLanguage': null},
      {'namingLanguage': 42},
    ]) {
      expect(
        AppSettings.fromJson(json).namingLanguage,
        NamingLanguage.simplifiedChinese,
      );
    }
  });

  test('命名语言可序列化且与界面语言独立', () {
    for (final language in NamingLanguage.values) {
      final settings = const AppSettings(language: 'zh')
          .copyWith(namingLanguage: language);
      expect(settings.toJson()['namingLanguage'], language.code);
      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.namingLanguage, language);
      expect(restored.language, 'zh');
      expect(restored.copyWith(language: 'en').namingLanguage, language);
    }
  });
}
