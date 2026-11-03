import 'dart:ui' as ui;
import 'dart:async';

import 'package:azusa/app/app.dart';
import 'package:azusa/app/router.dart';
import 'package:azusa/core/database/app_database.dart';
import 'package:azusa/core/window/desktop_window.dart';
import 'package:azusa/core/settings/settings.dart';
import 'package:azusa/core/settings/directory_sort.dart';
import 'package:azusa/core/settings/naming_language.dart';
import 'package:azusa/core/settings/naming_format.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:azusa/features/organizer/connections/connection_settings.dart';
import 'package:azusa/features/organizer/connections/ai_models.dart';
import 'package:azusa/features/organizer/ai/ai_usage.dart';
import 'package:azusa/features/organizer/ai/ai_usage_history.dart';
import 'package:azusa/features/organizer/dav/directory_favorites.dart';
import 'package:azusa/features/organizer/organizer_state.dart';
import 'package:azusa/features/organizer/startup_connection.dart';
import 'package:azusa/features/organizer/rename_plan.dart';
import 'package:azusa/features/organizer/dav/webdav.dart';
import 'package:azusa/shared/azusa_logo.dart';
import 'package:azusa/shared/widgets.dart';
import 'package:azusa/shared/loading_button.dart';
import 'package:azusa/shared/text_field_action.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
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

class PendingTestConnections extends TestConnections {
  final pending = Completer<void>();

  @override
  Future<void> save(ConnectionSettings value) async {
    await pending.future;
    state = AsyncData(value);
  }
}

class TestOrganizer extends OrganizerController {
  void updateAnalysis({AiUsage? usage, ModelPricing? pricing}) {
    state = state.copyWith(aiUsage: usage, pricing: pricing);
  }

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
        tmdbId: 1396,
        tmdbMediaType: TmdbMediaType.tv,
      ),
    ],
  );
}

class EntryInteractionOrganizer extends TestOrganizer {
  final opened = <String?>[];
  final renamed = <(String, String)>[];

  @override
  Future<void> open(String? path) async {
    opened.add(path);
    state = state.copyWith(directory: path, entries: []);
  }

  @override
  Future<void> renameEntry(DavEntry entry, String name) async {
    renamed.add((entry.path, name));
  }

  void setLocked({bool busy = false, bool executing = false}) {
    state = state.copyWith(busy: busy, executing: executing);
  }
}

class RenamePartsOrganizer extends EntryInteractionOrganizer {
  RenamePartsOrganizer(this.entry);
  final DavEntry entry;

  @override
  OrganizerState build() =>
      OrganizerState(directory: '/dav/', entries: [entry]);
}

class EmptyDirectoryOrganizer extends OrganizerController {
  @override
  OrganizerState build() => const OrganizerState(directory: '/dav/');
}

class AnalyzingOrganizer extends OrganizerController {
  @override
  OrganizerState build() => const OrganizerState(
    directory: '/dav/',
    busy: true,
    analyzing: true,
    entries: [DavEntry('/dav/a.mkv', false)],
  );
  @override
  void cancelSuggestions() {
    state = state.copyWith(busy: false, analyzing: false, message: 'AI 建议已中断');
  }
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

class MacWindow extends NoWindow {
  int closes = 0, minimizes = 0, maximizes = 0;
  @override
  bool get available => true;
  @override
  bool get macOS => true;
  @override
  Future<void> close() async => closes++;
  @override
  Future<void> minimize() async => minimizes++;
  @override
  Future<void> toggleMaximize() async => maximizes++;
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

class DirectoryScrollOrganizer extends OrganizerController {
  @override
  OrganizerState build() => OrganizerState(
    directory: '/dav/',
    entries: [
      for (var i = 0; i < 40; i++)
        DavEntry('/dav/folder${i.toString().padLeft(2, '0')}/', true),
    ],
  );

  @override
  Future<void> open(String? path) async {
    state = state.copyWith(
      directory: path ?? '/dav/',
      entries: path == '/dav/'
          ? [
              for (var i = 0; i < 40; i++)
                DavEntry('/dav/folder${i.toString().padLeft(2, '0')}/', true),
            ]
          : [const DavEntry('/dav/folder25/episode.mkv', false)],
    );
  }
}

class CompletedOrganizer extends TestOrganizer {
  @override
  OrganizerState build() =>
      const OrganizerState(directory: '/dav/', message: '已完成 1 项');
}

class FlattenOrganizer extends TestOrganizer {
  @override
  OrganizerState build() => const OrganizerState(
    directory: '/dav/',
    entries: [DavEntry('/dav/01/', true)],
    analysisEntries: [
      DavEntry('/dav/01/', true),
      DavEntry('/dav/01/raw.mkv', false),
    ],
    plan: [
      RenameItem(
        source: '/dav/01/raw.mkv',
        targetDirectory: '/dav/',
        targetName: 'Show - S03E01.mkv',
      ),
    ],
  );
}

void main() {
  for (final width in [390.0, 1280.0]) {
    testWidgets('模型获取选择及密钥显隐在 $width 宽度可用', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final window = NoWindow();
      final pending = Completer<List<String>>();
      Future<List<String>> response = pending.future;
      final requests = <ConnectionSettings>[];
      final container = ProviderContainer(
        overrides: [
          desktopWindowProvider.overrideWithValue(window),
          connectionSettingsProvider.overrideWith(SavableTestConnections.new),
          organizerProvider.overrideWith(TestOrganizer.new),
          initialSettingsProvider.overrideWithValue(
            const AppSettings(language: 'zh'),
          ),
          aiModelsLoaderProvider.overrideWithValue((settings) {
            requests.add(settings);
            return response;
          }),
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
      container.read(routerProvider).go('/settings');
      await tester.pumpAndSettle();
      Finder field(int i) => find.byKey(ValueKey('connection-field-$i'));
      Finder editable(int i) =>
          find.descendant(of: field(i), matching: find.byType(EditableText));
      await tester.ensureVisible(find.text('WebDAV').first);
      await tester.tap(find.text('WebDAV').first);
      await tester.pumpAndSettle();
      await tester.enterText(editable(2), 'webdav-password');
      expect(tester.widget<EditableText>(editable(2)).obscureText, isTrue);
      expect(
        tester.getSize(field(2)).height,
        closeTo(tester.getSize(field(1)).height, 0.1),
      );
      await tester.tap(find.byKey(const ValueKey('toggle-secret-2')));
      await tester.pumpAndSettle();
      expect(tester.widget<EditableText>(editable(2)).obscureText, isFalse);
      expect(
        tester.widget<EditableText>(editable(2)).controller.text,
        'webdav-password',
      );
      await tester.ensureVisible(find.text('AI Agent').first);
      await tester.tap(find.text('AI Agent').first);
      await tester.pumpAndSettle();

      await tester.enterText(editable(3), 'https://unsaved.test/v1');
      await tester.enterText(editable(5), 'unsaved-ai-key');
      expect(tester.widget<EditableText>(editable(5)).obscureText, isTrue);
      await tester.tap(find.byKey(const ValueKey('toggle-secret-5')));
      await tester.pumpAndSettle();
      expect(tester.widget<EditableText>(editable(5)).obscureText, isFalse);
      expect(
        tester.widget<EditableText>(editable(5)).controller.text,
        'unsaved-ai-key',
      );

      final fetch = find.byKey(const ValueKey('fetch-ai-models'));
      expect(find.ancestor(of: fetch, matching: field(4)), findsOneWidget);
      expect(
        find.descendant(
          of: fetch,
          matching: find.byIcon(FLucideIcons.refreshCw),
        ),
        findsOneWidget,
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      for (final action in [
        fetch,
        find.byKey(const ValueKey('toggle-secret-5')),
      ]) {
        await tester.ensureVisible(action);
        await mouse.moveTo(tester.getCenter(action));
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: action, matching: find.byType(FButton)),
          findsNothing,
        );
        final tappable = find.descendant(
          of: action,
          matching: find.byWidgetPredicate((widget) => widget is FTappable),
        );
        expect(tester.widget<FTappable>(tappable).focusedOutlineStyle, isNull);
        expect(tester.getSize(tappable), const Size(28, 28));
      }
      await mouse.removePointer();
      expect(find.text('获取模型'), findsNothing);
      for (final i in [4, 5]) {
        expect(
          tester.getSize(field(i)).height,
          closeTo(tester.getSize(field(3)).height, 0.1),
        );
      }
      await tester.ensureVisible(fetch);
      await tester.tap(fetch);
      await tester.pump();
      expect(tester.widget<TextFieldAction>(fetch).loading, isTrue);
      expect(tester.widget<FTextField>(field(4)).enabled, isFalse);
      expect(requests.single.aiUrl, 'https://unsaved.test/v1');
      expect(requests.single.aiKey, 'unsaved-ai-key');
      expect(
        container.read(connectionSettingsProvider).requireValue.aiKey,
        isEmpty,
      );
      pending.complete(['model-alpha', 'model-beta']);
      await tester.pumpAndSettle();
      final search = find.descendant(
        of: find.byKey(const ValueKey('ai-model-search')),
        matching: find.byType(EditableText),
      );
      await tester.enterText(search, 'BETA');
      await tester.pumpAndSettle();
      expect(find.text('model-alpha'), findsNothing);
      await tester.tap(find.text('model-beta'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(editable(4)).controller.text,
        'model-beta',
      );

      await tester.tap(fetch);
      await tester.pumpAndSettle();
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(editable(4)).controller.text,
        'model-beta',
      );
      response = Future.value([]);
      await tester.tap(fetch);
      await tester.pumpAndSettle();
      expect(find.text('服务未返回可用模型，仍可手动填写模型名称。'), findsOneWidget);
      expect(
        tester.widget<EditableText>(editable(4)).controller.text,
        'model-beta',
      );
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      // Complete the error only after a listener is installed by the request.
      final failure = Completer<List<String>>();
      response = failure.future;
      await tester.tap(fetch);
      await tester.pump();
      failure.completeError(const FormatException('AI /models 未返回有效 JSON'));
      await tester.pumpAndSettle();
      expect(find.textContaining('获取模型失败：'), findsOneWidget);
      expect(
        tester.widget<EditableText>(editable(4)).controller.text,
        'model-beta',
      );
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      await tester.enterText(editable(4), 'manual-model');
      final save = find.text('保存配置');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(
        container.read(connectionSettingsProvider).requireValue.model,
        'manual-model',
      );
      expect(
        container.read(connectionSettingsProvider).requireValue.aiKey,
        'unsaved-ai-key',
      );

      await tester.ensureVisible(find.text('TMDB').first);
      await tester.tap(find.text('TMDB').first);
      await tester.pumpAndSettle();
      await tester.enterText(editable(6), 'tmdb-key');
      expect(tester.widget<EditableText>(editable(6)).obscureText, isTrue);
      await tester.tap(find.byKey(const ValueKey('toggle-secret-6')));
      await tester.pumpAndSettle();
      expect(tester.widget<EditableText>(editable(6)).obscureText, isFalse);
      await tester.tap(find.byKey(const ValueKey('toggle-secret-6')));
      await tester.pumpAndSettle();
      expect(tester.widget<EditableText>(editable(6)).obscureText, isTrue);
      expect(
        tester.widget<EditableText>(editable(6)).controller.text,
        'tmdb-key',
      );
      container.read(routerProvider).go('/history');
      await tester.pumpAndSettle();
      container.read(routerProvider).go('/settings');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('AI Agent').first);
      await tester.tap(find.text('AI Agent').first);
      await tester.pumpAndSettle();
      expect(tester.widget<EditableText>(editable(5)).obscureText, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
  for (final width in [390.0, 1280.0]) {
    testWidgets('历史详情在 $width 宽度格式化时间并分开展示新旧路径', (tester) async {
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
          executionHistoryProvider.overrideWith(
            (_) async => [
              '2026-11-02 20:49:55.000001 准备重命名 /dav/Season 01/original.mkv → /dav/Season 01/new.mkv',
              '2026-11-02 20:49:56.117603 完成重命名 /dav/Season 01/original.mkv → /dav/Season 01/new.mkv',
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
      container.read(routerProvider).go('/history');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(FLucideIcons.chevronDown).last);
      await tester.pumpAndSettle();
      expect(find.text('原路径'), findsOneWidget);
      expect(find.text('新路径'), findsOneWidget);
      expect(find.text('开始于 2026-11-02 20:49:55'), findsOneWidget);
      expect(find.text('完成于 2026-11-02 20:49:56'), findsOneWidget);
      expect(find.textContaining('117603'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('AI 生成期间可点击停止并恢复生成按钮', (tester) async {
    final window = NoWindow();
    final container = ProviderContainer(
      overrides: [
        desktopWindowProvider.overrideWithValue(window),
        connectionSettingsProvider.overrideWith(TestConnections.new),
        organizerProvider.overrideWith(AnalyzingOrganizer.new),
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
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    container.read(routerProvider).go('/organize/assistant');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('停止生成'));
    await tester.pumpAndSettle();
    expect(container.read(organizerProvider).busy, isFalse);
    expect(find.text('AI 生成重命名建议'), findsOneWidget);
  });
  for (final width in [390.0, 1280.0]) {
    testWidgets('空目录提示在 $width 宽度下位于列表区域中心', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final window = NoWindow();
      final container = ProviderContainer(
        overrides: [
          desktopWindowProvider.overrideWithValue(window),
          connectionSettingsProvider.overrideWith(TestConnections.new),
          organizerProvider.overrideWith(EmptyDirectoryOrganizer.new),
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
      final region = tester.getRect(
        find.byKey(const ValueKey('nas-empty-state')),
      );
      final icon = tester.getRect(find.byIcon(FLucideIcons.folderOpen));
      final label = tester.getRect(find.text('此目录为空'));
      expect((icon.top + label.bottom) / 2, closeTo(region.center.dy, .1));
      expect(icon.center.dx, closeTo(region.center.dx, .1));
      expect(label.center.dx, closeTo(region.center.dx, .1));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('修改预览显示已核验匹配的 TMDB 跳转入口', (tester) async {
    final window = NoWindow();
    final container = ProviderContainer(
      overrides: [
        desktopWindowProvider.overrideWithValue(window),
        connectionSettingsProvider.overrideWith(TestConnections.new),
        organizerProvider.overrideWith(TestOrganizer.new),
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
    container.read(routerProvider).go('/organize/assistant/preview');
    await tester.pumpAndSettle();
    expect(find.text('在 TMDB 查看'), findsOneWidget);
    final button = tester.widget<FButton>(
      find.byKey(const ValueKey('tmdb-link-/dav/a.mkv')),
    );
    expect(button.onPress, isNotNull);
    expect(tester.takeException(), isNull);
  });
  for (final width in [390.0, 800.0, 1280.0]) {
    testWidgets('长目录面包屑在 $width 宽度省略并支持上级跳转', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final window = NoWindow();
      final container = ProviderContainer(
        overrides: [
          desktopWindowProvider.overrideWithValue(window),
          connectionSettingsProvider.overrideWith(TestConnections.new),
          organizerProvider.overrideWith(FavoritesOrganizer.new),
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
      final controller = container.read(organizerProvider.notifier);
      final longName = List.filled(
        12,
        'Azur.Lane.S01.2019.1080p.WEB-DL',
      ).join('.');
      await controller.open('/dav/library/series/$longName/');
      await tester.pumpAndSettle();
      final current = find.byKey(const ValueKey('directory-current-crumb'));
      final text = tester.widget<Text>(current);
      expect(text.data, longName);
      expect(text.overflow, TextOverflow.ellipsis);
      final bounds = tester.getRect(
        find.byKey(const ValueKey('directory-breadcrumb')),
      );
      expect(tester.getRect(current).right, lessThanOrEqualTo(bounds.right));
      expect(find.text('根目录'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('directory-ancestors')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('directory-ancestor-/dav/library/')),
      );
      await tester.pumpAndSettle();
      expect(container.read(organizerProvider).directory, '/dav/library/');
      await tester.tap(find.text('根目录'));
      await tester.pumpAndSettle();
      expect(container.read(organizerProvider).directory, '/dav/');
      expect(find.byKey(const ValueKey('directory-ancestors')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  for (final width in [390.0, 1280.0]) {
    testWidgets('NAS 排序菜单在 $width 宽度下即时重排并保存', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = MemorySettings();
      final window = NoWindow();
      final container = ProviderContainer(
        overrides: [
          desktopWindowProvider.overrideWithValue(window),
          connectionSettingsProvider.overrideWith(TestConnections.new),
          organizerProvider.overrideWith(LongOrganizer.new),
          settingsRepositoryProvider.overrideWithValue(repository),
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
      await tester.tap(find.byKey(const ValueKey('directory-sort')));
      await tester.pumpAndSettle();
      expect(find.text('名称：升序'), findsNothing);
      expect(find.text('名称：降序'), findsNothing);
      expect(find.byIcon(FLucideIcons.arrowUp), findsWidgets);
      await tester.tap(
        find.byKey(const ValueKey('directory-sort-nameAscending')),
      );
      await tester.pumpAndSettle();
      expect(repository.value.directorySort, DirectorySort.nameDescending);
      expect(
        container.read(settingsProvider).directorySort,
        DirectorySort.nameDescending,
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('/dav/episode9.mkv'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const ValueKey('/dav/episode8.mkv'))).dy,
        ),
      );
      final selectedItem = find.byKey(
        const ValueKey('directory-sort-nameAscending'),
      );
      expect(
        find.descendant(
          of: selectedItem,
          matching: find.byIcon(FLucideIcons.arrowDown),
        ),
        findsOneWidget,
      );
      await tester.tap(selectedItem);
      await tester.pumpAndSettle();
      expect(repository.value.directorySort, DirectorySort.nameAscending);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('只有单集文件夹时可进入整理，平铺预览可执行', (tester) async {
    final window = NoWindow();
    addTearDown(window.dispose);
    final container = ProviderContainer(
      overrides: [
        desktopWindowProvider.overrideWithValue(window),
        connectionSettingsProvider.overrideWith(TestConnections.new),
        organizerProvider.overrideWith(FlattenOrganizer.new),
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
    await tester.tap(find.text('整理此目录'));
    await tester.pumpAndSettle();
    expect(find.text('AI 生成重命名建议'), findsOneWidget);
    container.read(routerProvider).go('/organize/assistant/preview');
    await tester.pumpAndSettle();
    expect(find.text('/dav/01/raw.mkv'), findsOneWidget);
    expect(find.text('→ /dav/Show - S03E01.mkv'), findsOneWidget);
    expect(find.text('无法执行'), findsNothing);
    final button = tester.widget<FButton>(
      find.ancestor(of: find.text('确认并执行'), matching: find.byType(FButton)),
    );
    expect(button.onPress, isNotNull);
  });

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
  testWidgets('macOS 标题栏绘制左侧窗口按钮并响应点击', (tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final window = MacWindow();
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
    for (final key in ['mac-close', 'mac-minimize', 'mac-maximize']) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
      expect(tester.getSize(find.byKey(ValueKey(key))), const Size(20, 24));
    }
    final symbols = find.descendant(
      of: find.byKey(const ValueKey('mac-close')).first,
      matching: find.byType(AnimatedOpacity),
    );
    expect(tester.widget<AnimatedOpacity>(symbols).opacity, 0);
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('mac-close'))),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(symbols).opacity, 1);
    await mouse.moveTo(const Offset(400, 100));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(symbols).opacity, 0);
    await mouse.removePointer();
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('mac-close'))).dx,
      lessThan(30),
    );
    await tester.tap(find.byKey(const ValueKey('mac-minimize')));
    await tester.tap(find.byKey(const ValueKey('mac-maximize')));
    await tester.tap(find.byKey(const ValueKey('mac-close')));
    expect(window.minimizes, 1);
    expect(window.maximizes, 1);
    expect(window.closes, 1);
  });
  testWidgets('桌面设置页禁止滑动切换 Tab 并保留点击切换', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    tester.view.physicalSize = const Size(1280, 1000);
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
    container.read(routerProvider).go('/connections');
    await tester.pumpAndSettle();
    expect(
      tester.widget<FTabs>(find.byType(FTabs)).contentPhysics,
      isA<NeverScrollableScrollPhysics>(),
    );
    await tester.drag(find.text('语言').last, const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('语言').last, findsOneWidget);
    await tester.tap(find.text('WebDAV').first);
    await tester.pumpAndSettle();
    expect(find.text('测试 WebDAV'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
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
    testWidgets('命名语言和格式在 $width 宽度可独立选择并保存', (tester) async {
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
      expect(find.text('命名格式'), findsOneWidget);
      final help = find.byKey(const ValueKey('naming-format-help'));
      await tester.ensureVisible(help);
      await tester.tap(help);
      await tester.pumpAndSettle();
      expect(find.text('命名格式示例'), findsOneWidget);
      expect(find.text('星际穿越 (2014).mkv'), findsNWidgets(2));
      expect(find.text('星际穿越.2014.mkv'), findsNWidgets(2));
      for (final example in [
        '绝命毒师 - S01E01 - 试播集.mkv',
        '绝命毒师 - S01E01.mkv',
        '绝命毒师.S01E01.试播集.mkv',
        '绝命毒师.S01E01.mkv',
      ]) {
        expect(find.text(example), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.tap(
        find.byKey(const ValueKey('close-naming-format-examples')),
      );
      await tester.pumpAndSettle();
      expect(find.text('命名格式示例'), findsNothing);
      const formats = {
        '简洁': NamingFormat.compact,
        '点分隔': NamingFormat.dotted,
        '点分隔-简洁': NamingFormat.dottedCompact,
        '标准': NamingFormat.standard,
      };
      for (final option in formats.entries) {
        final select = find.byKey(const ValueKey('naming-format-select'));
        await tester.ensureVisible(select);
        await tester.tap(
          find.descendant(of: select, matching: find.byType(EditableText)),
        );
        await tester.pumpAndSettle();
        expect(find.text('含 TMDB ID'), findsNothing);
        await tester.tap(find.text(option.key).last);
        await tester.pumpAndSettle();
        expect(repository.value.namingFormat, option.value);
        expect(container.read(settingsProvider).namingFormat, option.value);
        expect(container.read(settingsProvider).language, 'zh');
        expect(
          container.read(settingsProvider).namingLanguage,
          NamingLanguage.english,
        );
      }
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

  testWidgets('进入子目录后返回时恢复父目录列表位置', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final window = NoWindow();
    addTearDown(window.dispose);
    final container = ProviderContainer(
      overrides: [
        desktopWindowProvider.overrideWithValue(window),
        connectionSettingsProvider.overrideWith(TestConnections.new),
        organizerProvider.overrideWith(DirectoryScrollOrganizer.new),
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
    final scrollable = find.descendant(
      of: list,
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('folder25'),
      350,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    final saved = tester.state<ScrollableState>(scrollable).position.pixels;
    expect(saved, greaterThan(0));
    await tester.tap(find.text('folder25'));
    await tester.pumpAndSettle();
    expect(tester.state<ScrollableState>(scrollable).position.pixels, 0);
    await tester.tap(find.bySemanticsLabel('返回上级'));
    await tester.pumpAndSettle();
    expect(container.read(organizerProvider).directory, '/dav/');
    expect(
      tester.state<ScrollableState>(scrollable).position.pixels,
      closeTo(saved, 1),
    );
    expect(find.text('folder25'), findsOneWidget);
  });

  testWidgets('执行完成后可直接从空预览返回目录选择', (tester) async {
    final window = NoWindow();
    addTearDown(window.dispose);
    final container = ProviderContainer(
      overrides: [
        desktopWindowProvider.overrideWithValue(window),
        connectionSettingsProvider.overrideWith(TestConnections.new),
        organizerProvider.overrideWith(CompletedOrganizer.new),
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
    container.read(routerProvider).go('/organize/assistant/preview');
    await tester.pumpAndSettle();
    await tester.tap(find.text('返回目录选择'));
    await tester.pumpAndSettle();
    expect(
      container.read(routerProvider).routeInformationProvider.value.uri.path,
      '/organize',
    );
    expect(find.text('目录选择'), findsWidgets);
  });

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

  for (final platform in [
    TargetPlatform.linux,
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.android,
  ]) {
    testWidgets('$platform NAS 选择、F2 与目录打开交互', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final window = NoWindow();
      addTearDown(window.dispose);
      final container = ProviderContainer(
        overrides: [
          desktopWindowProvider.overrideWithValue(window),
          connectionSettingsProvider.overrideWith(TestConnections.new),
          organizerProvider.overrideWith(EntryInteractionOrganizer.new),
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
      final controller = container.read(
        organizerProvider.notifier,
      ) as EntryInteractionOrganizer;
      final input = find.descendant(
        of: find.byKey(const ValueKey('rename-entry-name')),
        matching: find.byType(EditableText),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pumpAndSettle();
      expect(input, findsNothing);
      if (platform == TargetPlatform.android) {
        await tester.tap(find.text('a.mkv'));
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.f2);
        await tester.pumpAndSettle();
        expect(input, findsNothing);
        await tester.tap(find.text('season'));
        await tester.pumpAndSettle();
        expect(controller.opened, ['/dav/season/']);
        debugDefaultTargetPlatformOverride = null;
        return;
      }
      for (final name in ['a.mkv', 'season']) {
        await tester.tap(find.text(name), kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        expect(controller.opened, isEmpty);
        final selected = find.descendant(
          of: find.byKey(
            ValueKey(name == 'season' ? '/dav/season/' : '/dav/a.mkv'),
          ),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.selected == true,
          ),
        );
        expect(selected, findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.f2);
        await tester.pumpAndSettle();
        expect(
          tester.widget<EditableText>(input).controller.text,
          name == 'a.mkv' ? 'a' : name,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.f2);
        await tester.pumpAndSettle();
        expect(input, findsOneWidget);
        await tester.tap(find.text('取消').last);
        await tester.pumpAndSettle();
      }
      for (final executing in [false, true]) {
        controller.setLocked(busy: !executing, executing: executing);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.f2);
        await tester.pump();
        expect(input, findsNothing);
      }
      controller.setLocked();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pumpAndSettle();
      expect(tester.widget<EditableText>(input).controller.text, 'season');
      await tester.enterText(input, 'renamed-season');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FButton, '重命名'));
      await tester.pumpAndSettle();
      expect(controller.renamed, [('/dav/season/', 'renamed-season')]);
      for (final name in ['a.mkv', 'season']) {
        await tester.tap(find.text(name), kind: PointerDeviceKind.mouse);
        await tester.pump(const Duration(milliseconds: 60));
        await tester.tap(find.text(name), kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        expect(
          controller.opened,
          name == 'season' ? ['/dav/season/'] : isEmpty,
        );
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pumpAndSettle();
      expect(input, findsNothing);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    });
  }

  for (final (original, directory, base, suffix) in [
    ('episode.zh.srt', false, 'episode.zh', 'srt'),
    ('README', false, 'README', ''),
    ('.env', false, '.env', ''),
    ('.config.json', false, '.config', 'json'),
    ('Season.01', true, 'Season.01', ''),
  ]) {
    testWidgets('重命名分别编辑文件名和扩展名：$original', (tester) async {
      final window = NoWindow();
      addTearDown(window.dispose);
      final entry = DavEntry(
        '/dav/$original${directory ? '/' : ''}',
        directory,
      );
      final controller = RenamePartsOrganizer(entry);
      final container = ProviderContainer(
        overrides: [
          desktopWindowProvider.overrideWithValue(window),
          connectionSettingsProvider.overrideWith(TestConnections.new),
          organizerProvider.overrideWith(() => controller),
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
      await tester.tap(find.bySemanticsLabel('$original 的更多操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重命名'));
      await tester.pumpAndSettle();
      final name = find.descendant(
        of: find.byKey(const ValueKey('rename-entry-name')),
        matching: find.byType(EditableText),
      );
      final extension = find.descendant(
        of: find.byKey(const ValueKey('rename-entry-extension')),
        matching: find.byType(EditableText),
      );
      expect(tester.widget<EditableText>(name).controller.text, base);
      final submit = find.widgetWithText(FButton, '重命名');
      expect(tester.widget<FButton>(submit).onPress, isNull);
      if (!directory) {
        expect(tester.widget<EditableText>(extension).controller.text, suffix);
        await tester.enterText(extension, 'bad/ext');
        await tester.pumpAndSettle();
        expect(tester.widget<FButton>(submit).onPress, isNull);
        await tester.enterText(extension, 'mp4');
        await tester.pumpAndSettle();
        expect(tester.widget<FButton>(submit).onPress, isNotNull);
        await tester.enterText(extension, suffix);
        await tester.pumpAndSettle();
        expect(tester.widget<FButton>(submit).onPress, isNull);
        await tester.enterText(extension, '');
        await tester.pumpAndSettle();
        expect(tester.widget<EditableText>(name).controller.text, base);
      } else {
        expect(extension, findsNothing);
      }
      await tester.enterText(name, '');
      await tester.pumpAndSettle();
      expect(tester.widget<FButton>(submit).onPress, isNull);
      if (!directory) {
        await tester.enterText(extension, 'mkv');
        await tester.pumpAndSettle();
        expect(tester.widget<FButton>(submit).onPress, isNull);
      }
      await tester.enterText(name, '新名称');
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(controller.renamed, [(entry.path, directory ? '新名称' : '新名称.mkv')]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('NAS 文件和文件夹可通过下拉菜单打开重命名对话框', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
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
    for (final entry in ['a.mkv', 'season']) {
      await tester.tap(find.bySemanticsLabel('$entry 的更多操作'));
      await tester.pumpAndSettle();
      expect(find.text('重命名'), findsOneWidget);
      expect(
        find.descendant(
          of: find.widgetWithText(FItem, '重命名'),
          matching: find.byIcon(FLucideIcons.pencil),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('重命名'));
      await tester.pumpAndSettle();
      expect(find.text('重命名'), findsWidgets);
      final input = find.descendant(
        of: find.byKey(const ValueKey('rename-entry-name')),
        matching: find.byType(EditableText),
      );
      expect(
        tester.widget<EditableText>(input).controller.text,
        entry == 'a.mkv' ? 'a' : entry,
      );
      await tester.enterText(input, 'bad/name');
      await tester.pumpAndSettle();
      expect(find.textContaining('文件名无效'), findsOneWidget);
      await tester.tap(find.text('取消').last);
      await tester.pumpAndSettle();
    }
  });

  testWidgets('保存期间进度显示在保存按钮内并禁用测试按钮', (tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final window = NoWindow();
    addTearDown(window.dispose);
    final container = ProviderContainer(
      overrides: [
        desktopWindowProvider.overrideWithValue(window),
        connectionSettingsProvider.overrideWith(PendingTestConnections.new),
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
    await tester.tap(find.text('WebDAV').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存配置'));
    await tester.pump();
    final save = find.widgetWithText(LoadingButton, '保存配置');
    final test = find.widgetWithText(LoadingButton, '测试 WebDAV');
    expect(tester.widget<LoadingButton>(save).loading, isTrue);
    expect(tester.widget<LoadingButton>(test).onPress, isNull);
    expect(
      find.descendant(of: save, matching: find.byType(FCircularProgress)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: test, matching: find.byType(FCircularProgress)),
      findsNothing,
    );
    (container.read(
      connectionSettingsProvider.notifier,
    ) as PendingTestConnections).pending.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<LoadingButton>(save).loading, isFalse);
  });

  testWidgets('AI 用量卡片在价格到达及用量增长时更新费用', (tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
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
    container.read(routerProvider).go('/organize/assistant');
    await tester.pumpAndSettle();
    final controller =
        container.read(organizerProvider.notifier) as TestOrganizer;
    controller.updateAnalysis(
      usage: const AiUsage(responses: 1, inputTokens: 1000),
    );
    await tester.pumpAndSettle();
    expect(find.text('—'), findsWidgets);
    controller.updateAnalysis(
      pricing: const ModelPricing(input: 2, output: 8, source: 'test'),
    );
    await tester.pumpAndSettle();
    expect(find.text('\$0.002000'), findsOneWidget);
    controller.updateAnalysis(
      usage: const AiUsage(responses: 2, inputTokens: 2000, outputTokens: 100),
    );
    await tester.pump(const Duration(milliseconds: 225));
    expect(find.text('\$0.004800'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('\$0.004800'), findsOneWidget);
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
        matching: find.text('影视整理'),
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
          matching: find.text('影视整理'),
        );
        expect(tester.getSize(sidebar).width, 184);
        expect(
          tester.getRect(logo).left,
          closeTo(tester.getRect(menuIcon).left, 4),
        );
        expect(
          tester.getRect(find.text('Azusa')).left,
          closeTo(tester.getRect(menuLabel).left, 4),
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
