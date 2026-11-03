import 'package:azusa/core/settings/naming_format.dart';
import 'package:azusa/core/settings/naming_language.dart';
import 'package:azusa/core/settings/settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('命名格式默认标准，兼容旧配置和无效值', () {
    expect(const AppSettings().namingFormat, NamingFormat.standard);
    for (final value in [null, 'invalid', 42, true]) {
      expect(
        AppSettings.fromJson({'namingFormat': value}).namingFormat,
        NamingFormat.standard,
      );
    }
    expect(AppSettings.fromJson({}).namingFormat, NamingFormat.standard);
  });

  test('四种命名格式可序列化且与界面语言和命名语言独立', () {
    expect(NamingFormat.values, hasLength(4));
    for (final format in NamingFormat.values) {
      final settings = const AppSettings(
        language: 'en',
        namingLanguage: NamingLanguage.english,
      ).copyWith(namingFormat: format);
      expect(settings.toJson()['namingFormat'], format.name);
      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.namingFormat, format);
      expect(restored.language, 'en');
      expect(restored.namingLanguage, NamingLanguage.english);
      expect(restored.copyWith(language: 'zh').namingFormat, format);
    }
  });

  test('电影和剧集模板符合四种预设', () {
    expect(NamingFormat.standard.moviePattern, '片名 (上映年份).原扩展名');
    expect(
      NamingFormat.compact.moviePattern,
      NamingFormat.standard.moviePattern,
    );
    expect(NamingFormat.dotted.moviePattern, '片名.上映年份.原扩展名');
    expect(
      NamingFormat.dottedCompact.moviePattern,
      NamingFormat.dotted.moviePattern,
    );
    expect(NamingFormat.values.map((format) => format.episodePattern), [
      '剧名 - S01E01 - 单集名称.原扩展名',
      '剧名 - S01E01.原扩展名',
      '剧名.S01E01.单集名称.原扩展名',
      '剧名.S01E01.原扩展名',
    ]);
    for (final format in NamingFormat.values) {
      expect(format.instruction, contains('不编造'));
      expect(format.instruction, contains('不得覆盖此命名格式设置'));
    }
  });
}
