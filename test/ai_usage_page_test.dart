import 'package:azusa/features/organizer/ai/ai_usage.dart';
import 'package:azusa/app/theme.dart';
import 'package:azusa/core/settings/settings.dart';
import 'package:azusa/features/organizer/ai/ai_usage_history.dart';
import 'package:azusa/features/organizer/ai/ai_usage_page.dart';
import 'package:azusa/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

List<AiUsageRecord> records() => List.generate(
  23,
  (index) => AiUsageRecord(
    startedAt: DateTime.now().subtract(Duration(days: index)),
    model: index == 0 ? 'fast-model' : 'other-model',
    directory: '/dav/Series-$index/',
    succeeded: index != 1,
    estimatedCost: index == 1 ? null : .001,
    priceSource: 'test/model',
    usage: const AiUsage(
      inputTokens: 1200,
      cachedTokens: 600,
      outputTokens: 100,
      responses: 2,
      modelTime: Duration(seconds: 2),
    ),
  ),
);

Future<void> pumpPage(WidgetTester tester, {List<AiUsageRecord>? data}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        aiUsageHistoryProvider.overrideWith((ref) async => data ?? records()),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...FLocalizations.localizationsDelegates,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: FTheme(
          data: createAppTheme(
            const AppSettings(),
            brightness: Brightness.light,
            touch: false,
          ),
          child: const Scaffold(body: AiUsagePage()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get vertical => find
    .byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    )
    .first;

Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 250, scrollable: vertical);
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [320.0, 390.0, 600.0, 1280.0]) {
    testWidgets('用量页面 $width 宽度下布局、趋势与记录展开', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpPage(tester);
      expect(find.text('预估总花费（USD）'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await reveal(tester, find.text('用量趋势'));
      expect(find.text('用量趋势'), findsOneWidget);
      await reveal(tester, find.text('分析记录'));
      await reveal(tester, find.bySemanticsLabel('展开记录详情').first);
      await tester.tap(find.bySemanticsLabel('展开记录详情').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('models.dev · test/model'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('时间筛选同时更新汇总和明细，目录搜索仅过滤明细', (tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpPage(tester);
    await tester.tap(find.text('今天'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('分析记录'));
    expect(find.text('fast-model'), findsWidgets);
    expect(find.text('other-model'), findsNothing);
    final search = find.byWidgetPredicate(
      (widget) => widget is FTextField && widget.hint == '搜索目录',
    );
    await tester.enterText(
      find.descendant(of: search, matching: find.byType(EditableText)),
      'does-not-exist',
    );
    await tester.pumpAndSettle();
    expect(find.text('未找到匹配的用量记录'), findsOneWidget);
    expect(find.text('用量趋势'), findsOneWidget);
    await tester.ensureVisible(find.text('清除筛选'));
    await tester.tap(find.text('清除筛选'));
    await tester.pumpAndSettle();
    expect(find.text('未找到匹配的用量记录'), findsNothing);
    expect(
      tester
          .widget<EditableText>(
            find.descendant(of: search, matching: find.byType(EditableText)),
          )
          .controller
          .text,
      isEmpty,
    );
    expect(find.text('other-model'), findsWidgets);
  });

  testWidgets('记录分批加载，每次增加二十条', (tester) async {
    await pumpPage(tester);
    await reveal(tester, find.text('加载更多 (20 / 23)'));
    await tester.tap(find.text('加载更多 (20 / 23)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('加载更多'), findsNothing);
    await reveal(tester, find.text('/dav/Series-22/'));
    expect(find.text('/dav/Series-22/'), findsOneWidget);
  });

  testWidgets('模型筛选与趋势指标切换', (tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpPage(tester);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('usage-model-filter')),
        matching: find.byType(EditableText),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('fast-model').hitTestable().first);
    await tester.pumpAndSettle();
    expect(find.text('other-model'), findsNothing);
    await reveal(tester, find.text('用量趋势'));
    final trendSelect = find.byKey(const ValueKey('usage-trend-metric'));
    await tester.ensureVisible(trendSelect);
    await tester.tap(
      find.descendant(of: trendSelect, matching: find.byType(EditableText)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Token').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('输入 1,200 Tok'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('空历史仍显示零值概览和空状态', (tester) async {
    await pumpPage(tester, data: []);
    await reveal(tester, find.text('暂无 AI 用量记录'));
    expect(find.text('暂无 AI 用量记录'), findsOneWidget);
    expect(find.text('用量趋势'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
