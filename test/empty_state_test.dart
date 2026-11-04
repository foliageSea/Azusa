import 'package:azusa/app/theme.dart';
import 'package:azusa/core/logging/live_log_store.dart';
import 'package:azusa/core/settings/settings.dart';
import 'package:azusa/features/organizer/connections/model_picker.dart';
import 'package:azusa/features/settings/live_logs_section.dart';
import 'package:azusa/l10n/generated/app_localizations.dart';
import 'package:azusa/shared/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:logging/logging.dart';

Widget app(
  Widget child, {
  Brightness brightness = Brightness.light,
  double scale = 1,
}) => MaterialApp(
  locale: const Locale('zh'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    ...FLocalizations.localizationsDelegates,
    ...GlobalMaterialLocalizations.delegates,
  ],
  home: FTheme(
    data: createAppTheme(
      const AppSettings(),
      brightness: brightness,
      touch: false,
    ),
    child: MediaQuery(
      data: MediaQueryData(
        size: const Size(320, 800),
        textScaler: TextScaler.linear(scale),
      ),
      child: Scaffold(body: child),
    ),
  ),
);

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('空状态在 $brightness 窄屏大字号下可读', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        app(
          EmptyNotice(
            '未找到匹配的文件或文件夹',
            icon: FLucideIcons.search,
            child: FButton(
              variant: .outline,
              mainAxisSize: MainAxisSize.min,
              onPress: () {},
              child: const Text('清除筛选'),
            ),
          ),
          brightness: brightness,
          scale: 1.5,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('未找到匹配的文件或文件夹'), findsOneWidget);
      expect(find.byIcon(FLucideIcons.search), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('模型无搜索结果可清除搜索且保留选中项', (tester) async {
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => FButton(
            onPress: () => showModelPicker(context, [
              'model-a',
              'model-b',
            ], selected: 'model-a'),
            child: const Text('选择模型'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('选择模型'));
    await tester.pumpAndSettle();
    final search = find.descendant(
      of: find.byKey(const ValueKey('ai-model-search')),
      matching: find.byType(EditableText),
    );
    await tester.enterText(search, 'missing');
    await tester.pumpAndSettle();
    expect(find.text('未找到匹配的模型'), findsOneWidget);
    await tester.tap(find.text('清除搜索'));
    await tester.pumpAndSettle();
    expect(tester.widget<EditableText>(search).controller.text, isEmpty);
    expect(find.text('model-a'), findsOneWidget);
    expect(find.byIcon(FLucideIcons.check), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('日志筛选空状态可清除并保留暂停', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = LiveLogStore();
    addTearDown(store.dispose);
    store.add(level: Level.INFO, time: DateTime.now(), text: 'retained-entry');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [liveLogStoreProvider.overrideWithValue(store)],
        child: app(const LiveLogsSection()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pause-logs')));
    final search = find.descendant(
      of: find.byKey(const ValueKey('log-search')),
      matching: find.byType(EditableText),
    );
    await tester.enterText(search, 'missing');
    await tester.pumpAndSettle();
    expect(find.text('未找到匹配的日志'), findsOneWidget);
    await tester.tap(find.text('清除筛选'));
    await tester.pumpAndSettle();
    expect(tester.widget<EditableText>(search).controller.text, isEmpty);
    expect(find.text('恢复'), findsOneWidget);
    expect(store.snapshot, hasLength(1));
    await tester.tap(find.byKey(const ValueKey('clear-logs')));
    await tester.pumpAndSettle();
    expect(find.text('暂无日志'), findsOneWidget);
    expect(find.text('未找到匹配的日志'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
