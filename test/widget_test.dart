import 'package:azusa/app/app.dart';
import 'package:azusa/app/router.dart';
import 'package:azusa/core/database/app_database.dart';
import 'package:azusa/core/window/desktop_window.dart';
import 'package:azusa/core/settings/settings.dart';
import 'package:azusa/core/settings/naming_language.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:azusa/features/organizer/connections/connection_settings.dart';
import 'package:azusa/features/organizer/ai/ai_usage.dart';
import 'package:azusa/features/organizer/ai/ai_usage_history.dart';
import 'package:azusa/features/organizer/dav/directory_favorites.dart';
import 'package:azusa/features/organizer/organizer_state.dart';
import 'package:azusa/features/organizer/startup_connection.dart';
import 'package:azusa/features/organizer/rename_plan.dart';
import 'package:azusa/features/organizer/dav/webdav.dart';
import 'package:azusa/shared/azusa_logo.dart';
import 'package:azusa/shared/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

class TestConnections extends ConnectionSettingsController {
  @override
  Future<ConnectionSettings> build() async => const ConnectionSettings(
    webdavUrl: 'https://nas.test/dav/',
    model: 'test-model',
  );
}

class SavableTestConnections extends TestConnections {
  @override
  Future<void> save(ConnectionSettings value) async {
    state = AsyncData(value);
  }
}

class TestOrganizer extends OrganizerController {
  @override
  OrganizerState build() => const OrganizerState(
    directory: '/dav/',
    aiUsage: AiUsage(
      inputTokens: 1200,
      outputTokens: 120,
      responses: 2,
      modelTime: Duration(seconds: 3),
    ),
    pricing: ModelPricing(input: 2, output: 8, source: 'test'),
    entries: [DavEntry('/dav/a.mkv', false), DavEntry('/dav/season/', true)],
    plan: [
      RenameItem(
        source: '/dav/a.mkv',
        targetName: '剧集 - S01E01.mkv',
        reason: 'TMDB 1396 / S1E1',
      ),
    ],
  );
}

class NoWindow extends DesktopWindowController {
  @override
  bool get available => false;
  @override
  bool get macOS => false;
  @override
  bool get maximized => false;
  @override
  bool get fullScreen => false;
  @override
  bool get focused => true;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> drag() async {}
  @override
  Future<void> minimize() async {}
  @override
  Future<void> toggleMaximize() async {}
  @override
  Future<void> close() async {}
}

class FavoritesOrganizer extends TestOrganizer {
  void beginDirectoryLoad() {
    state = state.copyWith(busy: true, message: '');
  }

  void finishDirectoryLoad() {
    state = state.copyWith(busy: false);
  }

  @override
  Future<void> open(String? path) async {
    state = state.copyWith(directory: path ?? '/dav/');
  }
}

class BackNavigationOrganizer extends TestOrganizer {
  final opened = <String?>[];

  @override
  OrganizerState build() => const OrganizerState(
    directory: '/dav/series/season/',
    entries: [DavEntry('/dav/series/season/episode.mkv', false)],
  );

  @override
  Future<void> open(String? path) async {
    opened.add(path);
    state = state.copyWith(directory: path);
  }

  void setBusy(bool value) {
    state = state.copyWith(busy: value);
  }
}

class MemoryFavorites extends DirectoryFavoritesRepository {
  MemoryFavorites()
    : super(AppDatabase(open: () async => throw UnimplementedError()));
  final paths = <String>[];
  @override
  Future<List<String>> load(NasScope scope) async => [...paths];
  @override
  Future<void> add(NasScope scope, String path) async {
    if (!paths.contains(path)) paths.add(path);
  }

  @override
  Future<void> remove(NasScope scope, String path) async => paths.remove(path);
}

class MemorySettings implements SettingsRepository {
  AppSettings value = const AppSettings();
  @override
  Future<AppSettings> load() async => value;
  @override
  Future<void> save(AppSettings settings) async {
    value = settings;
  }
}

class LongOrganizer extends OrganizerController {
  @override
  OrganizerState build() => OrganizerState(
    directory: '/dav/',
    entries: List.generate(30, (i) => DavEntry('/dav/episode$i.mkv', false)),
    plan: List.generate(
      30,
      (i) => RenameItem(
        source: '/dav/episode$i.mkv',
        targetName: '剧集 - S01E${i + 1}.mkv',
      ),
    ),
  );

  void completeProposal() {
    state = state.copyWith(busy: true, message: '正在查询剧集资料…');
    state = state.copyWith(busy: false, message: '建议已生成');
  }
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .localesTestValue = const [
      Locale('zh'),
    ];
  });
  tearDown(() {
    TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher
        .clearLocalesTestValue();
  });
  for (final width in [390.0, 1280.0]) {
    testWidgets('步骤跳转和快速返回在 $width 宽度不叠加透明页面', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final window = NoWindow();
      addTearDown(window.dispose);
      final container = ProviderContainer(
        overrides: [
          desktopWindowProvider.overrideWithValue(window),
          connectionSettingsProvider.overrideWith(TestConnections.new),
          organizerProvider.overrideWith(TestOrganizer.new),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const StarterApp(),
        ),
      );
      await tester.pumpAndSettle();
      final router = container.read(routerProvider);
      for (final path in [
        '/organize/assistant',
        '/organize/assistant/preview',
        '/organize/assistant',
        '/organize',
      ]) {
        router.go(path);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        expect(find.byKey(const ValueKey('organizer-stepper')), findsOneWidget);
        final background = find.byKey(
          const ValueKey('organizer-page-background'),
        );
        expect(background, findsOneWidget);
        final color = tester.widget<ColoredBox>(background).color;
        expect(color.a, 1);
        final bounds = tester.getRect(background);
        expect(
          bounds.contains(
            tester.getCenter(find.byKey(const ValueKey('organizer-stepper'))),
          ),
          isTrue,
        );
        if (path.endsWith('/preview')) {
          expect(find.text('整理要求（可选）'), findsNothing);
          expect(find.text('确认并执行'), findsOneWidget);
        } else if (path.endsWith('/assistant')) {
          expect(find.text('断开连接'), findsNothing);
          expect(find.text('整理要求（可选）'), findsOneWidget);
        } else {
          expect(find.text('整理要求（可选）'), findsNothing);
          expect(find.text('断开连接'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('English 界面在 $width 宽度下即时切换且不影响命名语言', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = MemorySettings();
      final window = NoWindow();
      addTearDown(window.dispose);
      final container = ProviderContainer(
        overrides: [
          desktopWindowProvider.overrideWithValue(window),
          connectionSettingsProvider.overrideWith(TestConnections.new),
          organizerProvider.overrideWith(TestOrganizer.new),
          settingsRepositoryProvider.overrideWithValue(repository),
          executionHistoryProvider.overrideWith((ref) async => []),
          aiUsageHistoryProvider.overrideWith((ref) async => []),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const StarterApp(),
        ),
      );
      await tester.pumpAndSettle();
      container.read(routerProvider).go('/settings');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('language-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English').last);
      await tester.pumpAndSettle();
      expect(find.text('General'), findsOneWidget);
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('Settings'), findsWidgets);
      expect(find.text('设置'), findsNothing);
      expect(repository.value.language, 'en');
      expect(repository.value.namingLanguage, NamingLanguage.simplifiedChinese);
      await tester.ensureVisible(find.text('WebDAV').first);
      await tester.tap(find.text('WebDAV').first);
      await tester.pumpAndSettle();
      expect(find.text('WebDAV URL'), findsOneWidget);
      expect(find.text('Username'), findsOneWidget);
      expect(find.text('Save configuration'), findsOneWidget);
      await tester.ensureVisible(find.text('HTTP proxy').first);
      await tester.tap(find.text('HTTP proxy').first);
      await tester.pumpAndSettle();
      expect(find.text('Proxy mode'), findsOneWidget);
      expect(find.text('Use proxy for AI'), findsOneWidget);
      await tester.ensureVisible(find.text('TMDB').first);
      await tester.tap(find.text('TMDB').first);
      await tester.pumpAndSettle();
      expect(find.text('Naming language'), findsOneWidget);
      container.read(routerProvider).go('/organize');
      await tester.pumpAndSettle();
      expect(find.text('Disconnect'), findsOneWidget);
      expect(find.text('Organize this directory'), findsOneWidget);
      for (var index = 0; index < 3; index++) {
        expect(
          tester
              .widget<FTappable>(find.byKey(ValueKey('organizer-step-$index')))
              .onPress,
          isNull,
        );
      }
      container.read(routerProvider).go('/organize/assistant');
      await tester.pumpAndSettle();
      expect(find.text('Generate rename suggestions'), findsOneWidget);
      expect(find.text('Organizing requirements (optional)'), findsOneWidget);
      expect(
        tester
            .widget<FTappable>(find.byKey(const ValueKey('organizer-step-0')))
            .onPress,
        isNotNull,
      );
      expect(
        tester
            .widget<FTappable>(find.byKey(const ValueKey('organizer-step-2')))
            .onPress,
        isNull,
      );
      container.read(routerProvider).go('/organize/assistant/preview');
      await tester.pumpAndSettle();
      expect(find.text('Confirm and execute'), findsOneWidget);
      expect(find.text('New file name'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('organizer-step-1')));
      await tester.pumpAndSettle();
      expect(
        container.read(routerProvider).routeInformationProvider.value.uri.path,
        '/organize/assistant',
      );
      await tester.tap(find.byKey(const ValueKey('organizer-step-0')));
      await tester.pumpAndSettle();
      expect(
        container.read(routerProvider).routeInformationProvider.value.uri.path,
        '/organize',
      );
      container.read(routerProvider).go('/history');
      await tester.pumpAndSettle();
      expect(find.text('No execution history yet'), findsOneWidget);
      container.read(routerProvider).go('/ai-usage');
      await tester.pumpAndSettle();
      expect(find.text('No AI analysis usage yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await container
          .read(settingsProvider.notifier)
          .update((s) => s.copyWith(language: 'zh'));
      await tester.pumpAndSettle();
      expect(find.text('暂无 AI 分析用量'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
  for (final width in [390.0, 1280.0]) {
    testWidgets('命名语言在 $width 宽度可独立选择并保存', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = MemorySettings();
      final window = NoWindow();
      addTearDown(window.dispose);
      final container = ProviderContainer(
        overrides: [
          desktopWindowProvider.overrideWithValue(window),
          connectionSettingsProvider.overrideWith(TestConnections.new),
          organizerProvider.overrideWith(TestOrganizer.new),
          settingsRepositoryProvider.overrideWithValue(repository),
          initialSettingsProvider.overrideWithValue(
            const AppSettings(language: 'zh'),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const StarterApp(),
        ),
      );
      await tester.pumpAndSettle();
      container.read(routerProvider).go('/settings');
      await tester.pumpAndSettle();
      expect(find.text('命名语言'), findsNothing);
      expect(find.text('日志'), findsNothing);
      expect(find.text('运行环境'), findsNothing);
      expect(find.text('关于模板'), findsNothing);
      expect(find.text('常规设置'), findsNothing);
      await tester.ensureVisible(find.text('TMDB').first);
      await tester.tap(find.text('TMDB').first);
      await tester.pumpAndSettle();
      expect(find.text('命名语言'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('naming-language-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English').last);
      await tester.pumpAndSettle();
      expect(repository.value.namingLanguage, NamingLanguage.english);
      expect(
        container.read(settingsProvider).namingLanguage,
        NamingLanguage.english,
      );
      expect(container.read(settingsProvider).language, 'zh');
      expect(
        container.read(organizerProvider).plan.single.targetName,
        '剧集 - S01E01.mkv',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.linux]) {
    testWidgets('$platform 返回操作打开上级目录且不越过根目录', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final window = NoWindow();
      addTearDown(window.dispose);
      final container = ProviderContainer(
        overrides: [
          desktopWindowProvider.overrideWithValue(window),
          connectionSettingsProvider.overrideWith(TestConnections.new),
          organizerProvider.overrideWith(BackNavigationOrganizer.new),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const StarterApp(),
        ),
      );
      await tester.pumpAndSettle();
      final controller =
          container.read(organizerProvider.notifier) as BackNavigationOrganizer;
      Future<void> back() async {
        if (platform == TargetPlatform.android) {
          await tester.binding.handlePopRoute();
        } else {
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
            buttons: kBackMouseButton,
          );
          await mouse.down(
            tester.getCenter(find.byKey(const ValueKey('nas-file-list'))),
          );
          await mouse.up();
          await mouse.removePointer();
        }
        await tester.pump(const Duration(milliseconds: 300));
      }

      controller.setBusy(true);
      await tester.pump();
      await back();
      expect(controller.opened, isEmpty);
      controller.setBusy(false);
      await tester.pumpAndSettle();
      await back();
      expect(container.read(organizerProvider).directory, '/dav/series/');
      await back();
      expect(container.read(organizerProvider).directory, '/dav/');
      await back();
      expect(controller.opened, ['/dav/series/', '/dav/']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      debugDefaultTargetPlatformOverride = null;
    });
  }

  for (final width in [390.0, 1280.0]) {
    testWidgets('NAS 文件列表在 $width 宽度下内部滚动且工具栏固定', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final window = NoWindow();
      addTearDown(window.dispose);
      final container = ProviderContainer(
        overrides: [
          desktopWindowProvider.overrideWithValue(window),
          connectionSettingsProvider.overrideWith(TestConnections.new),
          organizerProvider.overrideWith(LongOrganizer.new),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const StarterApp(),
        ),
      );
      await tester.pumpAndSettle();
      final list = find.byKey(const ValueKey('nas-file-list'));
      final browser = find.byKey(const ValueKey('nas-browser'));
      final disconnect = find.text('断开连接');
      final refresh = find.byIcon(FLucideIcons.refreshCw);
      final breadcrumb = find.text('根目录');
      final action = find.text('整理此目录');
      final browserBefore = tester.getRect(browser);
      final disconnectBefore = tester.getRect(disconnect);
      final refreshBefore = tester.getRect(refresh);
      final breadcrumbBefore = tester.getRect(breadcrumb);
      final actionBefore = tester.getRect(action);
      final bottomActions = find.byKey(
        const ValueKey('organizer-bottom-actions'),
      );
      for (final icon in [
        FLucideIcons.arrowUp,
        FLucideIcons.refreshCw,
        FLucideIcons.star,
      ]) {
        expect(
          find.descendant(of: bottomActions, matching: find.byIcon(icon)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: browser, matching: find.byIcon(icon)),
          findsNothing,
        );
      }
      expect(refreshBefore.center.dy, closeTo(actionBefore.center.dy, 1));
      expect(browserBefore.bottom, greaterThan(actionBefore.top - 100));
      expect(
        find.ancestor(of: browser, matching: find.byType(Scrollable)),
        findsNothing,
      );
      final scrollable = find.descendant(
        of: list,
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('episode9.mkv'),
        250,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
      expect(
        tester.state<ScrollableState>(scrollable).position.pixels,
        greaterThan(0),
      );
      expect(tester.getRect(browser), browserBefore);
      expect(tester.getRect(disconnect), disconnectBefore);
      expect(tester.getRect(refresh), refreshBefore);
      expect(tester.getRect(breadcrumb), breadcrumbBefore);
      expect(tester.getRect(action), actionBefore);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('四个连接配置 Tab 使用保存气泡提示', (tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final window = NoWindow();
    addTearDown(window.dispose);
    final container = ProviderContainer(
      overrides: [
        desktopWindowProvider.overrideWithValue(window),
        connectionSettingsProvider.overrideWith(SavableTestConnections.new),
        organizerProvider.overrideWith(TestOrganizer.new),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const StarterApp(),
      ),
    );
    await tester.pumpAndSettle();
    container.read(routerProvider).go('/connections');
    await tester.pumpAndSettle();
    for (final tab in ['WebDAV', 'AI Agent', 'TMDB', 'HTTP 代理']) {
      await tester.ensureVisible(find.text(tab).first);
      await tester.tap(find.text(tab).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存配置'));
      await tester.pumpAndSettle();
      expect(find.text('配置已保存'), findsOneWidget);
      expect(find.byIcon(FLucideIcons.circleCheck), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('配置已保存'),
          matching: find.byType(PageContent),
        ),
        findsNothing,
      );
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(find.text('配置已保存'), findsNothing);
    }
    await tester.tap(find.text('直连').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('系统代理').last);
    await tester.pumpAndSettle();
    expect(find.text('代理地址（http://主机:端口）'), findsNothing);
    await tester.tap(find.text('保存配置'));
    await tester.pumpAndSettle();
    expect(
      container.read(connectionSettingsProvider).requireValue.proxyMode,
      ProxyMode.system,
    );
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    await tester.tap(find.text('系统代理').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('手动代理').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).last, 'invalid-proxy');
    await tester.tap(find.text('保存配置'));
    await tester.pumpAndSettle();
    expect(find.textContaining('保存失败：'), findsOneWidget);
    expect(find.byIcon(FLucideIcons.circleX), findsOneWidget);
    expect(
      find.ancestor(
        of: find.textContaining('保存失败：'),
        matching: find.byType(PageContent),
      ),
      findsNothing,
    );
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关于').first);
    await tester.pumpAndSettle();
    expect(find.text('Azusa'), findsNWidgets(2));
    expect(find.text('AzuIndex'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('亮暗模式快捷切换并保存设置', (tester) async {
    final repository = MemorySettings();
    final window = NoWindow();
    addTearDown(window.dispose);
    final container = ProviderContainer(
      overrides: [
        desktopWindowProvider.overrideWithValue(window),
        connectionSettingsProvider.overrideWith(TestConnections.new),
        organizerProvider.overrideWith(TestOrganizer.new),
        settingsRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const StarterApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('切换暗色模式'));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).themeMode, ThemeMode.dark);
    expect(repository.value.themeMode, ThemeMode.dark);
    expect(find.byIcon(FLucideIcons.sun), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('切换亮色模式'));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).themeMode, ThemeMode.light);
    expect(repository.value.themeMode, ThemeMode.light);
    expect(tester.takeException(), isNull);
  });
  for (final width in [390.0, 1280.0]) {
    testWidgets('目录收藏、取消与快速跳转在 $width 宽度可用', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = MemoryFavorites();
      addTearDown(repository.database.close);
      final scope = nasScope(
        const ConnectionSettings(webdavUrl: 'https://nas.test/dav/'),
      );
      final path = '/dav/${Uri.encodeComponent('很长的中文剧集收藏目录' * 10)}/';
      await repository.add(scope, path);
      final window = NoWindow();
      addTearDown(window.dispose);
      final container = ProviderContainer(
        overrides: [
          desktopWindowProvider.overrideWithValue(window),
          connectionSettingsProvider.overrideWith(TestConnections.new),
          organizerProvider.overrideWith(FavoritesOrganizer.new),
          directoryFavoritesRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const StarterApp(),
        ),
      );
      await tester.pumpAndSettle();
      final browser = find.byKey(const ValueKey('nas-browser'));
      final browserBefore = tester.getRect(browser);
      final rowBefore = tester.getRect(find.text('a.mkv'));
      final controller =
          container.read(organizerProvider.notifier) as FavoritesOrganizer;
      controller.beginDirectoryLoad();
      await tester.pump();
      expect(tester.getRect(browser), browserBefore);
      expect(tester.getRect(find.text('a.mkv')), rowBefore);
      expect(find.text('正在处理…'), findsNothing);
      controller.finishDirectoryLoad();
      await tester.pumpAndSettle();
      expect(tester.getRect(browser), browserBefore);
      expect(find.text(Uri.decodeComponent(path)), findsNothing);
      await tester.tap(find.bySemanticsLabel('收藏当前目录'));
      await tester.pumpAndSettle();
      expect(find.text('收藏列表'), findsNothing);
      expect(await tester.runAsync(() => repository.load(scope)), [
        path,
        '/dav/',
      ]);
      expect(find.bySemanticsLabel('取消收藏当前目录'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('取消收藏当前目录'));
      await tester.pumpAndSettle();
      expect(await tester.runAsync(() => repository.load(scope)), [path]);
      await tester.tap(find.bySemanticsLabel('收藏列表'));
      await tester.pumpAndSettle();
      expect(find.text('收藏列表'), findsOneWidget);
      expect(find.bySemanticsLabel('关闭收藏'), findsNothing);
      expect(find.text('收藏当前目录'), findsNothing);
      final label = Uri.decodeComponent(path);
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(container.read(organizerProvider).directory, path);
      expect(find.bySemanticsLabel('取消收藏当前目录'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('收藏列表'));
      await tester.pumpAndSettle();
      final removeButton = find.bySemanticsLabel('移除收藏 $label');
      final remove = tester.widget<FButton>(
        find.ancestor(of: removeButton, matching: find.byType(FButton)).first,
      );
      expect(remove.variant, FButtonVariant.destructive);
      await tester.tap(removeButton);
      await tester.pumpAndSettle();
      expect(await tester.runAsync(() => repository.load(scope)), isEmpty);
      final barrier = tester.getRect(find.byType(ModalBarrier).last);
      await tester.tapAt(Offset(barrier.center.dx, barrier.top + 10));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('收藏当前目录'), findsOneWidget);
      await tester.tap(find.text('断开连接'));
      await tester.pumpAndSettle();
      expect(find.text('连接 NAS'), findsOneWidget);
      expect(container.read(organizerProvider).directory, isEmpty);
      expect(find.byIcon(FLucideIcons.star), findsNothing);
      expect(find.text('收藏目录'), findsNothing);
      expect(container.read(organizerProvider).entries, isEmpty);
      expect(container.read(organizerProvider).plan, isEmpty);
      expect(container.read(organizerProvider).aiUsage, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('底部操作固定，完成提示使用气泡且不重复显示', (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final window = NoWindow();
    addTearDown(window.dispose);
    final container = ProviderContainer(
      overrides: [
        desktopWindowProvider.overrideWithValue(window),
        connectionSettingsProvider.overrideWith(TestConnections.new),
        organizerProvider.overrideWith(LongOrganizer.new),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const StarterApp(),
      ),
    );
    await tester.pumpAndSettle();
    for (final (path, label) in [
      ('/organize', '整理此目录'),
      ('/organize/assistant/preview', '确认并执行'),
    ]) {
      container.read(routerProvider).go(path);
      await tester.pumpAndSettle();
      final button = find.text(label);
      final before = tester.getRect(button);
      final breadcrumb = find.byKey(const ValueKey('organizer-stepper'));
      final breadcrumbBefore = tester.getRect(breadcrumb);
      expect(before.bottom, lessThan(800));
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(tester.getRect(button), before);
      expect(tester.getRect(breadcrumb), breadcrumbBefore);
      expect(
        find.ancestor(
          of: breadcrumb,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
          ),
        ),
        findsNothing,
      );
      expect(
        find.ancestor(of: button, matching: find.byType(Scrollable)),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    }
    (container.read(organizerProvider.notifier) as LongOrganizer)
        .completeProposal();
    await tester.pumpAndSettle();
    expect(find.text('建议已生成'), findsOneWidget);
    expect(find.byIcon(FLucideIcons.circleCheck), findsOneWidget);
    expect(
      tester.widget<Icon>(find.byIcon(FLucideIcons.circleCheck)).semanticLabel,
      '成功',
    );
    expect(
      find.ancestor(of: find.text('建议已生成'), matching: find.byType(FAlert)),
      findsNothing,
    );
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.text('建议已生成'), findsNothing);
    container.read(routerProvider).go('/organize/assistant');
    await tester.pumpAndSettle();
    expect(find.text('建议已生成'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  for (final width in [390.0, 800.0, 1280.0, 1920.0]) {
    testWidgets('浏览、预览、设置在 $width 宽度下无布局异常', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final window = NoWindow();
      final container = ProviderContainer(
        overrides: [
          desktopWindowProvider.overrideWithValue(window),
          connectionSettingsProvider.overrideWith(TestConnections.new),
          organizerProvider.overrideWith(TestOrganizer.new),
          aiUsageHistoryProvider.overrideWith(
            (ref) async => [
              AiUsageRecord(
                startedAt: DateTime(2026, 11, 2),
                model: 'test-model',
                directory: '/dav/',
                usage: const AiUsage(
                  inputTokens: 1200,
                  outputTokens: 120,
                  responses: 2,
                  modelTime: Duration(seconds: 3),
                ),
                succeeded: true,
                estimatedCost: 0.00336,
              ),
            ],
          ),
          executionHistoryProvider.overrideWith(
            (ref) async => [
              '完成重命名 a.mkv → 新名称.mkv',
              '2026-11-02 09:48:54.720825 准备重命名 /dav/Season 01/old.mkv → /dav/Season 01/new.mkv',
              '2026-11-02 09:48:54.738497 完成重命名 /dav/Season 01/old.mkv → /dav/Season 01/new.mkv',
            ],
          ),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(window.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const StarterApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('断开连接'), findsOneWidget);
      expect(find.byIcon(FLucideIcons.upload), findsNothing);
      expect(find.byIcon(FLucideIcons.folderPlus), findsNothing);
      expect(find.bySemanticsLabel('season 的更多操作'), findsNothing);
      expect(find.bySemanticsLabel('a.mkv 的更多操作'), findsNothing);
      expect(find.byType(FPopoverMenu), findsNothing);
      expect(find.byIcon(FLucideIcons.ellipsis), findsNothing);
      final headerTitle = find.descendant(
        of: find.byWidgetPredicate((widget) => widget is FHeader),
        matching: find.text('剧集整理'),
      );
      final card = tester.getRect(find.byType(FCard).first);
      final breadcrumb = tester.getRect(
        find.byKey(const ValueKey('organizer-stepper')),
      );
      expect(tester.getRect(headerTitle).left, closeTo(card.left, .1));
      expect(breadcrumb.left, closeTo(card.left, .1));
      expect(card.top - breadcrumb.bottom, lessThanOrEqualTo(16));
      expect(find.text('Azusa'), width >= 1024 ? findsOneWidget : findsNothing);
      expect(
        find.byType(AzusaLogo),
        width >= 600 ? findsOneWidget : findsNothing,
      );
      final routeSurface = tester.widget<ClipRRect>(
        find.byKey(const ValueKey('route-surface')),
      );
      expect(
        routeSurface.borderRadius,
        width >= 600
            ? const BorderRadius.only(topLeft: Radius.circular(16))
            : BorderRadius.zero,
      );
      if (width >= 600) {
        final sidebarContext = tester.element(find.byType(FSidebar));
        final sidebarData = tester.widget<FSidebarData>(
          find.descendant(
            of: find.byType(FSidebar),
            matching: find.byType(FSidebarData),
          ),
        );
        final decoration = sidebarData.style.decoration as BoxDecoration;
        expect(decoration.color, sidebarContext.theme.colors.muted);
        expect(decoration.border, isNull);
      }
      if (width >= 1024) {
        final sidebar = find.byType(FSidebar);
        final logo = find.descendant(
          of: sidebar,
          matching: find.byType(AzusaLogo),
        );
        final menuIcon = find.descendant(
          of: sidebar,
          matching: find.byIcon(FLucideIcons.folderPen),
        );
        final menuLabel = find.descendant(
          of: sidebar,
          matching: find.text('剧集整理'),
        );
        expect(tester.getSize(sidebar).width, 184);
        expect(
          tester.getRect(logo).left,
          closeTo(tester.getRect(menuIcon).left, .1),
        );
        expect(
          tester.getRect(find.text('Azusa')).left,
          closeTo(tester.getRect(menuLabel).left, .1),
        );
      }
      expect(tester.takeException(), isNull);
      expect(find.text('AI 生成重命名建议'), findsNothing);
      expect(find.text('确认并执行'), findsNothing);
      await tester.tap(find.text('整理此目录'));
      await tester.pumpAndSettle();
      expect(
        container.read(routerProvider).routeInformationProvider.value.uri.path,
        '/organize/assistant',
      );
      expect(find.text('连接 NAS'), findsNothing);
      expect(find.text('AI 生成重命名建议'), findsOneWidget);
      expect(find.text('输入 Tok'), findsOneWidget);
      expect(find.text('1200'), findsOneWidget);
      expect(find.text('40.0'), findsOneWidget);
      expect(find.text('\$0.003360'), findsOneWidget);
      final instruction = find.byType(FTextField);
      final editable = tester.widget<EditableText>(
        find.descendant(of: instruction, matching: find.byType(EditableText)),
      );
      expect(editable.minLines, 3);
      expect(editable.maxLines, 6);
      expect(editable.keyboardType, TextInputType.multiline);
      expect(editable.textInputAction, TextInputAction.newline);
      expect(editable.onSubmitted, isNull);
      await tester.enterText(
        find.descendant(of: instruction, matching: find.byType(EditableText)),
        '保留中文剧名',
      );
      await tester.tap(find.text('查看修改预览'));
      await tester.pumpAndSettle();
      expect(
        container.read(routerProvider).routeInformationProvider.value.uri.path,
        '/organize/assistant/preview',
      );
      expect(find.text('AI 生成重命名建议'), findsNothing);
      expect(find.text('AI 分析用量'), findsOneWidget);
      expect(find.textContaining('串行'), findsNothing);
      expect(
        find.ancestor(
          of: find.bySemanticsLabel('返回上一步'),
          matching: find.byWidgetPredicate((widget) => widget is FHeader),
        ),
        findsOneWidget,
      );
      final vertical = find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .last;
      await tester.scrollUntilVisible(
        find.text('确认并执行'),
        300,
        scrollable: vertical,
      );
      await tester.pumpAndSettle();
      expect(find.text('确认并执行'), findsOneWidget);
      final newName = find.byType(FTextField).last;
      await tester.enterText(
        find.descendant(of: newName, matching: find.byType(EditableText)),
        '用户修改 - S01E01.mkv',
      );
      await tester.pump();
      expect(
        container.read(organizerProvider).plan.single.targetName,
        '用户修改 - S01E01.mkv',
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.bySemanticsLabel('返回上一步'));
      await tester.pumpAndSettle();
      expect(find.text('保留中文剧名'), findsOneWidget);
      await tester.tap(find.text('查看修改预览'));
      await tester.pumpAndSettle();
      expect(find.text('用户修改 - S01E01.mkv'), findsOneWidget);
      container.read(routerProvider).go('/ai-usage');
      await tester.pumpAndSettle();
      expect(find.text('累计输入 Tok'), findsOneWidget);
      expect(find.text('累计输出 Tok'), findsOneWidget);
      expect(find.text('预估总花费（USD）'), findsOneWidget);
      if (width < mobileBreakpoint) {
        final analyses = tester.getRect(find.text('分析次数'));
        final requests = tester.getRect(find.text('模型请求'));
        expect(analyses.top, closeTo(requests.top, 0.1));
        expect(requests.left, greaterThan(analyses.right));
        final input = tester.getRect(find.text('累计输入 Tok'));
        expect(input.left, closeTo(analyses.left, 0.1));
        expect(input.top - analyses.top, lessThan(100));
      }
      expect(find.text('分析记录'), findsOneWidget);
      expect(tester.takeException(), isNull);
      container.read(routerProvider).go('/connections');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('WebDAV').first);
      await tester.tap(find.text('WebDAV').first);
      await tester.pumpAndSettle();
      expect(find.text('WebDAV 地址'), findsOneWidget);
      expect(find.text('OpenAI 兼容 API 基础地址'), findsNothing);
      final webdavUrl = find.descendant(
        of: find.byType(FTextField).first,
        matching: find.byType(EditableText),
      );
      await tester.enterText(webdavUrl, '');
      await tester.tap(find.text('测试 WebDAV'));
      await tester.pumpAndSettle();
      expect(find.textContaining('连接失败：'), findsOneWidget);
      expect(find.byIcon(FLucideIcons.circleX), findsOneWidget);
      expect(
        tester.widget<Icon>(find.byIcon(FLucideIcons.circleX)).semanticLabel,
        '错误',
      );
      expect(
        find.ancestor(
          of: find.textContaining('连接失败：'),
          matching: find.byType(PageContent),
        ),
        findsNothing,
      );
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(find.textContaining('连接失败：'), findsNothing);
      await tester.enterText(webdavUrl, 'https://nas.test/dav/');
      final username = find.byType(FTextField).at(1);
      await tester.enterText(
        find.descendant(of: username, matching: find.byType(EditableText)),
        '未保存的用户名',
      );
      await tester.tap(find.text('AI Agent').first);
      await tester.pumpAndSettle();
      expect(find.text('OpenAI 兼容 API 基础地址'), findsOneWidget);
      expect(find.text('WebDAV 地址'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('TMDB').first);
      await tester.tap(find.text('TMDB').first);
      await tester.pumpAndSettle();
      expect(find.text('API Key / Read Access Token'), findsOneWidget);
      await tester.ensureVisible(find.text('HTTP 代理').first);
      await tester.tap(find.text('HTTP 代理').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('WebDAV 使用代理'));
      await tester.pumpAndSettle();
      expect(find.text('WebDAV 使用代理'), findsOneWidget);
      await tester.ensureVisible(find.text('关于').first);
      await tester.tap(find.text('关于').first);
      await tester.pumpAndSettle();
      expect(find.text('MiSans 字体许可'), findsOneWidget);
      expect(find.text('保存配置'), findsNothing);
      await tester.ensureVisible(find.text('WebDAV').first);
      await tester.tap(find.text('WebDAV').first);
      await tester.pumpAndSettle();
      expect(find.text('未保存的用户名'), findsOneWidget);
      expect(find.text('保存配置'), findsOneWidget);
      expect(
        find.ancestor(of: find.text('保存配置'), matching: find.byType(FCard)),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('HTTP 代理').first);
      await tester.tap(find.text('HTTP 代理').first);
      await tester.pumpAndSettle();
      final proxyCheckbox = tester.widget<FCheckbox>(
        find.ancestor(
          of: find.text('WebDAV 使用代理'),
          matching: find.byType(FCheckbox),
        ),
      );
      expect(proxyCheckbox.value, isTrue);
      expect(find.text('保存配置'), findsOneWidget);
      expect(tester.takeException(), isNull);
      container.read(routerProvider).go('/organize/assistant/preview');
      await tester.pumpAndSettle();
      expect(find.text('用户修改 - S01E01.mkv'), findsOneWidget);
      container.read(routerProvider).pop();
      await tester.pumpAndSettle();
      expect(find.text('AI 生成重命名建议'), findsOneWidget);
      container.read(routerProvider).pop();
      await tester.pumpAndSettle();
      expect(find.text('断开连接'), findsOneWidget);
      expect(
        container.read(organizerProvider).plan.single.targetName,
        '用户修改 - S01E01.mkv',
      );
      container.read(routerProvider).go('/history');
      await tester.pumpAndSettle();
      expect(find.text('2 项操作'), findsOneWidget);
      expect(find.text('old.mkv'), findsOneWidget);
      expect(find.text('new.mkv'), findsOneWidget);
      expect(find.text('已完成'), findsNWidgets(2));
      expect(find.textContaining('/dav/Season 01/old.mkv'), findsNothing);
      await tester.tap(find.bySemanticsLabel('展开记录详情').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('/dav/Season 01/old.mkv'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('未选择目录时，整理子路由返回目录页', (tester) async {
    final window = NoWindow();
    addTearDown(window.dispose);
    final container = ProviderContainer(
      overrides: [
        startupConnectionProvider.overrideWith((ref) async {}),
        desktopWindowProvider.overrideWithValue(window),
        connectionSettingsProvider.overrideWith(TestConnections.new),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const StarterApp(),
      ),
    );
    await tester.pumpAndSettle();
    final router = container.read(routerProvider);
    for (final path in ['/organize/assistant', '/organize/assistant/preview']) {
      router.go(path);
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/organize');
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
