import 'package:azusa/l10n/generated/app_localizations_en.dart';
import 'package:azusa/l10n/generated/app_localizations_zh.dart';
import 'package:azusa/shared/runtime_localization.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final en = AppLocalizationsEn();
  final zh = AppLocalizationsZh();
  test('运行状态、嵌套错误和匹配依据可显示英文', () {
    expect(
      localizeRuntimeMessage(en, zh.queryingMetadata),
      en.queryingMetadata,
    );
    expect(localizeRuntimeMessage(en, zh.aiAnalyzing(2)), en.aiAnalyzing(2));
    expect(
      localizeRuntimeMessage(en, zh.completedItemCount(3)),
      en.completedItemCount(3),
    );
    expect(
      localizeRuntimeMessage(en, zh.executionStopped(zh.targetExists)),
      en.executionStopped(en.targetExists),
    );
    expect(
      localizeRuntimeMessage(en, zh.matchEvidence('1', '2', '中文标题', '1396')),
      en.matchEvidence('1', '2', '中文标题', '1396'),
    );
  });
  test('文件名、未知服务信息和中文界面原文不被修改', () {
    const name = '目标已存在.mkv';
    expect(
      localizeRuntimeMessage(en, zh.targetNameExists(name)),
      en.targetNameExists(name),
    );
    expect(
      localizeRuntimeMessage(en, 'Service custom error'),
      'Service custom error',
    );
    expect(
      localizeRuntimeMessage(zh, zh.queryingMetadata),
      zh.queryingMetadata,
    );
    expect(
      localizeRuntimeMessage(en, zh.invalidFileNameReplace('/', '／')),
      en.invalidFileNameReplace('/', '／'),
    );
  });
}
