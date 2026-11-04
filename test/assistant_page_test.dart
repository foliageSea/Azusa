import 'package:azusa/app/app.dart';
import 'package:azusa/app/router.dart';
import 'package:azusa/core/database/app_database.dart';
import 'package:azusa/core/window/desktop_window.dart';
import 'package:azusa/features/assistant/assistant_state.dart';
import 'package:azusa/features/organizer/ai/agent_activity.dart';
import 'package:azusa/features/organizer/ai/folder_layout.dart';
import 'package:azusa/features/organizer/ai/ai_usage.dart';
import 'package:azusa/features/organizer/connections/connection_settings.dart';
import 'package:azusa/features/organizer/connections/webdav_connections.dart';
import 'package:azusa/features/organizer/dav/webdav.dart';
import 'package:azusa/features/organizer/dav/directory_favorites.dart';
import 'package:azusa/features/organizer/organizer_state.dart';
import 'package:azusa/features/organizer/rename_plan.dart';
import 'package:azusa/features/organizer/startup_connection.dart';
import 'package:azusa/shared/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

class _Connections extends ConnectionSettingsController {
  @override
  Future<ConnectionSettings> build() async => const ConnectionSettings(
    webdavUrl: 'https://nas.test/dav/',
    model: 'test-model',
  );
}

class _NoWindow extends DesktopWindowController {
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

final _root = '/dav/${Uri.encodeComponent('待整理')}/';

List<RenameItem> _plan() => [
  RenameItem(
    source: '${_root}raw.1.mkv',
    targetName: '绝命毒师 - S01E01 - 试播集.mkv',
    tmdbId: 1396,
    tmdbMediaType: TmdbMediaType.tv,
    mediaTitle: '绝命毒师',
    mediaYear: 2008,
    seasonNumber: 1,
    episodeNumber: 1,
    scope: _root,
  ),
  RenameItem(
    source: '${_root}movie.mkv',
    targetName: '星际穿越 (2014).mkv',
    tmdbId: 157336,
    tmdbMediaType: TmdbMediaType.movie,
    mediaTitle: '星际穿越',
    mediaYear: 2014,
    scope: _root,
  ),
];

class _Organizer extends OrganizerController {
  _Organizer({String? directory}) : directory = directory ?? _root;

  final String directory;
  var proposals = 0;

  @override
  Future<void> open(String? path) async {
    state = OrganizerState(
      directory: path ?? '/dav/',
      entries: [DavEntry('${path ?? '/dav/'}movie.mkv', false)],
    );
  }

  @override
  OrganizerState build() => OrganizerState(
    directory: directory,
    entries: [
      DavEntry('${directory}raw.1.mkv', false),
      DavEntry('${directory}movie.mkv', false),
    ],
  );

  @override
  Future<void> propose({
    String instruction = '',
    FolderLayout? folderLayout,
    void Function(AgentActivity activity)? onActivity,
    void Function(FolderLayout layout)? onLayout,
  }) async {
    proposals++;
    state = state.copyWith(busy: true, analyzing: true);
    const scan = AgentActivity(
      key: 'scan',
      kind: AgentActivityKind.scan,
      subject: '/dav/待整理/',
    );
    onActivity?.call(scan.succeed(count: 2));
    const search = AgentActivity(
      key: 'tool-1',
      kind: AgentActivityKind.searchTv,
      subject: '绝命毒师',
    );
    onActivity?.call(search.succeed(count: 3));
    const movie = AgentActivity(
      key: 'tool-2',
      kind: AgentActivityKind.getMovie,
    );
    onActivity?.call(movie.succeed(title: '星际穿越', date: '2014-11-05'));
    const failed = AgentActivity(
      key: 'tool-3',
      kind: AgentActivityKind.searchMovie,
      subject: '未知影片',
      number: 1999,
    );
    onActivity?.call(failed.fail('请求过于频繁，请稍后重试'));
    state = state.copyWith(
      busy: false,
      analyzing: false,
      plan: applyFolderLayout(_plan(), _root, folderLayout!),
      aiUsage: const AiUsage(
        inputTokens: 1000,
        outputTokens: 200,
        responses: 2,
        modelTime: Duration(seconds: 2),
      ),
      message: '建议已生成',
    );
  }
}

class _PickerDav extends WebDavClient {
  _PickerDav(super.settings);

  bool fail = false;
  int requests = 0;
  int closes = 0;

  @override
  Future<List<DavEntry>> list(String path) async {
    requests++;
    if (fail) throw StateError('读取目录失败');
    return [
      if (path == _root) const DavEntry('/dav/other/', true),
      if (path == '/dav/') DavEntry(_root, true),
      DavEntry('${path}movie.mkv', false),
    ];
  }

  @override
  void close() {
    closes++;
    super.close();
  }
}

class _Favorites extends DirectoryFavoritesRepository {
  _Favorites()
    : super(AppDatabase(open: () async => throw UnimplementedError()));

  final _paths = <String>[];

  @override
  Future<List<String>> load(NasScope scope) async => [..._paths];

  @override
  Future<void> add(NasScope scope, String path) async {
    if (!_paths.contains(path)) _paths.add(path);
  }

  @override
  Future<void> remove(NasScope scope, String path) async => _paths.remove(path);
}

Future<(ProviderContainer, _Organizer)> _pump(
  WidgetTester tester,
  double width, {
  String? directory,
  _PickerDav? pickerDav,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final window = _NoWindow();
  final favorites = _Favorites();
  addTearDown(favorites.database.close);
  final organizer = _Organizer(directory: directory);
  final container = ProviderContainer(
    overrides: [
      desktopWindowProvider.overrideWithValue(window),
      directoryFavoritesRepositoryProvider.overrideWithValue(favorites),
      startupConnectionProvider.overrideWith((ref) async {}),
      connectionSettingsProvider.overrideWith(_Connections.new),
      organizerProvider.overrideWith(() => organizer),
      webDavConnectionsProvider.overrideWith((ref) async => []),
      if (pickerDav != null)
        webDavFactoryProvider.overrideWithValue((_) => pickerDav),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(window.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const StarterApp()),
  );
  await tester.pumpAndSettle();
  return (container, organizer);
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
    testWidgets('助手目录选择器在 $width 宽度共享文件页收藏', (tester) async {
      const connection = ConnectionSettings(webdavUrl: 'https://nas.test/dav/');
      final dav = _PickerDav(connection);
      final (container, _) = await _pump(tester, width, pickerDav: dav);
      final scope = nasScope(connection);
      final repository = container.read(directoryFavoritesRepositoryProvider);
      await repository.add(scope, '/dav/other/');

      await tester.tap(find.byKey(const ValueKey('assistant-directory')));
      await tester.pumpAndSettle();
      final favorites = find.byKey(
        const ValueKey('directory-picker-favorites'),
      );
      final favoriteButton = find.byKey(
        const ValueKey('directory-picker-favorite'),
      );
      final confirm = find.byKey(const ValueKey('directory-picker-confirm'));
      expect(
        find.descendant(of: favorites, matching: find.byType(Text)),
        findsNothing,
      );
      expect(
        tester.getRect(favorites).center.dy,
        closeTo(tester.getRect(confirm).center.dy, 1),
      );
      expect(
        tester.getRect(favoriteButton).right,
        lessThan(tester.getRect(confirm).left),
      );
      await tester.tap(
        find.byKey(const ValueKey('directory-picker-favorites')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('/dav/other/'));
      await tester.pumpAndSettle();
      expect(find.text('other'), findsOneWidget);
      expect(container.read(organizerProvider).directory, _root);
      final favorite = find.byKey(const ValueKey('directory-picker-favorite'));
      expect(tester.widget<FButton>(favorite).semanticsLabel, '取消收藏当前目录');

      await tester.tap(favorite);
      await tester.pumpAndSettle();
      expect(
        container.read(directoryFavoritesProvider(scope)).requireValue,
        isEmpty,
      );
      expect(await repository.load(scope), isEmpty);

      await tester.tap(favorite);
      await tester.pumpAndSettle();
      expect(container.read(directoryFavoritesProvider(scope)).requireValue, [
        '/dav/other/',
      ]);
      expect(await repository.load(scope), ['/dav/other/']);

      await repository.add(scope, _root);
      container.invalidate(directoryFavoritesProvider(scope));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('directory-picker-favorites')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('/dav/待整理/'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('directory-picker-path')),
          matching: find.text('待整理'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [390.0, 1280.0]) {
    testWidgets('助手在 $width 宽度独立选择目录且确认前不改变对话', (tester) async {
      final dav = _PickerDav(
        const ConnectionSettings(webdavUrl: 'https://nas.test/dav/'),
      );
      final (container, _) = await _pump(tester, width, pickerDav: dav);
      container.read(assistantProvider.notifier).grantConsent();
      await container.read(assistantProvider.notifier).send('整理');
      await tester.pumpAndSettle();
      final messages = container.read(assistantProvider).messages;
      final plan = container.read(organizerProvider).plan;

      await tester.tap(find.byKey(const ValueKey('assistant-directory')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('directory-picker')), findsOneWidget);
      expect(find.text('movie.mkv'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('directory-picker-folder-/dav/other/')),
      );
      await tester.pumpAndSettle();
      expect(find.text('没有子目录'), findsOneWidget);
      expect(container.read(organizerProvider).directory, _root);
      expect(container.read(organizerProvider).plan, same(plan));
      expect(container.read(assistantProvider).messages, same(messages));
      expect(
        container.read(routerProvider).routeInformationProvider.value.uri.path,
        '/assistant',
      );

      await tester.tap(find.byKey(const ValueKey('directory-picker-confirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('directory-picker')), findsNothing);
      expect(container.read(organizerProvider).directory, '/dav/other/');
      expect(container.read(organizerProvider).plan, isEmpty);
      expect(container.read(assistantProvider).messages, isEmpty);
      expect(container.read(assistantProvider.notifier).hasConsent, isFalse);
      expect(dav.closes, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('取消目录选择保留目录、对话与方案', (tester) async {
    final dav = _PickerDav(
      const ConnectionSettings(webdavUrl: 'https://nas.test/dav/'),
    );
    final (container, _) = await _pump(tester, 1280, pickerDav: dav);
    container.read(assistantProvider.notifier).grantConsent();
    await container.read(assistantProvider.notifier).send('整理');
    await tester.pumpAndSettle();
    final state = container.read(organizerProvider);
    final assistant = container.read(assistantProvider);
    await tester.tap(find.byKey(const ValueKey('assistant-directory')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('directory-picker-folder-/dav/other/')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(container.read(organizerProvider), same(state));
    expect(container.read(assistantProvider), same(assistant));
    expect(dav.closes, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('目录选择支持筛选、返回上级和根目录', (tester) async {
    final dav = _PickerDav(
      const ConnectionSettings(webdavUrl: 'https://nas.test/dav/'),
    );
    await _pump(tester, 1280, pickerDav: dav);
    await tester.tap(find.byKey(const ValueKey('assistant-directory')));
    await tester.pumpAndSettle();
    final filter = find.descendant(
      of: find.byKey(const ValueKey('directory-picker-filter')),
      matching: find.byType(EditableText),
    );
    await tester.enterText(filter, 'missing');
    await tester.pumpAndSettle();
    expect(find.text('未找到匹配的文件或文件夹'), findsOneWidget);
    await tester.enterText(filter, 'other');
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('directory-picker-folder-/dav/other/')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('directory-picker-parent')));
    await tester.pumpAndSettle();
    expect(find.text('根目录'), findsOneWidget);
    expect(
      tester
          .widget<FButton>(
            find.byKey(const ValueKey('directory-picker-parent')),
          )
          .onPress,
      isNull,
    );
    await tester.tap(find.byKey(ValueKey('directory-picker-folder-$_root')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('directory-picker-root')));
    await tester.pumpAndSettle();
    expect(find.text('根目录'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('未选目录时从根目录开始且读取失败可重试', (tester) async {
    final dav = _PickerDav(
      const ConnectionSettings(webdavUrl: 'https://nas.test/dav/'),
    )..fail = true;
    final (container, _) = await _pump(
      tester,
      1280,
      directory: '',
      pickerDav: dav,
    );
    await tester.tap(find.text('选择目录'));
    await tester.pumpAndSettle();
    expect(find.text('重试'), findsOneWidget);
    expect(
      tester
          .widget<FButton>(
            find.byKey(const ValueKey('directory-picker-confirm')),
          )
          .onPress,
      isNull,
    );
    expect(container.read(organizerProvider).directory, isEmpty);
    dav.fail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('根目录'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('directory-picker-confirm')));
    await tester.pumpAndSettle();
    expect(container.read(organizerProvider).directory, '/dav/');
    expect(tester.takeException(), isNull);
  });

  testWidgets('目录选择面包屑支持折叠祖先目录和鼠标侧键返回', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final dav = _PickerDav(
      const ConnectionSettings(webdavUrl: 'https://nas.test/dav/'),
    );
    await _pump(
      tester,
      1280,
      directory: '${_root}season/episode/',
      pickerDav: dav,
    );
    await tester.tap(find.byKey(const ValueKey('assistant-directory')));
    await tester.pumpAndSettle();
    final path = find.byKey(const ValueKey('directory-picker-path'));
    expect(path, findsOneWidget);
    expect(
      find.descendant(of: path, matching: find.text('episode')),
      findsOneWidget,
    );
    expect(find.text('没有子目录'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(EmptyState),
        matching: find.byIcon(FLucideIcons.folderOpen),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('directory-ancestors')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('directory-ancestor-$_root')));
    await tester.pumpAndSettle();
    expect(find.text('待整理'), findsOneWidget);

    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kBackMouseButton,
    );
    await mouse.down(
      tester.getCenter(find.byKey(const ValueKey('directory-picker'))),
    );
    await mouse.up();
    await mouse.removePointer();
    await tester.pumpAndSettle();
    expect(find.text('根目录'), findsOneWidget);
    expect(find.byKey(const ValueKey('directory-picker')), findsOneWidget);
    expect(dav.requests, 3);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  for (final width in [390.0, 1100.0, 1466.0]) {
    testWidgets('长目录名在 $width 宽度下不溢出且保留新对话按钮', (tester) async {
      const name = '僵尸100～在成为僵尸前要做的100件事～ (2023) [1080p BluRay]';
      final (container, _) = await _pump(
        tester,
        width,
        directory: '/dav/${Uri.encodeComponent(name)}/',
      );
      expect(tester.takeException(), isNull);

      final directory = find.byKey(const ValueKey('assistant-directory'));
      final label = find.descendant(of: directory, matching: find.text(name));
      expect(label, findsOneWidget);
      expect(
        tester.getRect(label).right,
        lessThanOrEqualTo(tester.getRect(directory).right),
      );

      container.read(assistantProvider.notifier).grantConsent();
      await container.read(assistantProvider.notifier).send('整理');
      await tester.pumpAndSettle();

      final reset = find.byKey(const ValueKey('assistant-reset'));
      expect(reset, findsOneWidget);
      expect(
        tester.getRect(directory).right,
        lessThanOrEqualTo(tester.getRect(reset).left),
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [390.0, 1280.0]) {
    testWidgets('整理助手作为首页在 $width 宽度展示对话、工具过程与方案', (tester) async {
      final (container, organizer) = await _pump(tester, width);
      expect(
        container.read(routerProvider).routeInformationProvider.value.uri.path,
        '/assistant',
      );
      expect(find.text('整理助手'), findsWidgets);
      expect(find.text('要怎么整理这个目录？'), findsOneWidget);
      expect(find.text('待整理'), findsOneWidget);

      await tester.tap(find.text('识别并整理这个目录'));
      await tester.pumpAndSettle();
      expect(find.text('将此目录发送给 AI 分析？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(organizer.proposals, 0);

      await tester.tap(find.text('识别并整理这个目录'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始分析'));
      await tester.pumpAndSettle();
      expect(organizer.proposals, 1);

      expect(find.text('识别并整理这个目录'), findsOneWidget);
      expect(find.text('已完成 3 次查询'), findsOneWidget);
      expect(find.textContaining('1200 Tok'), findsOneWidget);
      expect(find.text('已生成整理方案，请核对后执行。'), findsOneWidget);
      expect(find.text('整理方案 · 第 1 版'), findsWidgets);
      expect(find.text('1 部电影'), findsOneWidget);
      expect(find.text('1 部剧集'), findsOneWidget);
      expect(find.text('2 个文件将修改'), findsOneWidget);
      expect(find.text('新建 3 个文件夹'), findsWidgets);
      expect(find.text('搜索剧集「绝命毒师」'), findsNothing);

      await tester.tap(find.text('已完成 3 次查询'));
      await tester.pumpAndSettle();
      expect(find.text('读取目录'), findsOneWidget);
      expect(find.text('2 个条目'), findsOneWidget);
      expect(find.text('搜索剧集「绝命毒师」'), findsOneWidget);
      expect(find.text('3 个候选'), findsOneWidget);
      expect(find.text('核对电影「星际穿越」'), findsOneWidget);
      expect(find.text('2014-11-05'), findsOneWidget);
      expect(find.text('搜索电影「未知影片」· 1999'), findsOneWidget);
      expect(find.text('请求过于频繁，请稍后重试'), findsOneWidget);

      if (width < 960) {
        expect(find.byKey(const ValueKey('assistant-plan-list')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('assistant-view-plan')));
        await tester.pumpAndSettle();
      } else {
        expect(find.byKey(const ValueKey('assistant-view-plan')), findsNothing);
      }
      expect(find.byKey(const ValueKey('assistant-plan-list')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('assistant-plan-list')),
          matching: find.byType(FTooltip),
        ),
        findsNothing,
      );
      expect(find.text('目录结构'), findsOneWidget);
      expect(find.text('绝命毒师 (2008)'), findsOneWidget);
      expect(find.text('Season 01'), findsOneWidget);
      expect(find.text('星际穿越 (2014)'), findsOneWidget);
      expect(find.text('绝命毒师 - S01E01 - 试播集.mkv'), findsOneWidget);
      expect(find.byType(EditableText).evaluate().length, lessThanOrEqualTo(1));
      final file = find.byKey(ValueKey('plan-file-${_root}raw.1.mkv'));
      await tester.tap(file);
      await tester.pumpAndSettle();
      expect(find.text('原路径'), findsOneWidget);
      expect(find.text('新路径'), findsOneWidget);
      await tester.enterText(
        find.descendant(
          of: find.byKey(ValueKey('plan-name-${_root}raw.1.mkv')),
          matching: find.byType(EditableText),
        ),
        '僵尸100～在成为僵尸前要做的100件事～ - S01E01 - 死者的光明磊落.mkv',
      );
      await tester.pumpAndSettle();
      expect(find.text('确认并执行'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('目录树支持折叠、文件详情改名、勾选与全选', (tester) async {
    final (container, _) = await _pump(tester, 1280);
    container.read(assistantProvider.notifier).grantConsent();
    await container.read(assistantProvider.notifier).send('整理');
    await tester.pumpAndSettle();

    final source = '${_root}raw.1.mkv';
    final file = find.byKey(ValueKey('plan-file-$source'));
    await tester.tap(find.text('Season 01'));
    await tester.pumpAndSettle();
    expect(file, findsNothing);
    await tester.tap(find.text('Season 01'));
    await tester.pumpAndSettle();
    expect(file, findsOneWidget);

    await tester.tap(file);
    await tester.pumpAndSettle();
    expect(find.text('原路径'), findsOneWidget);
    expect(find.text('新路径'), findsOneWidget);
    expect(find.byKey(ValueKey('tmdb-link-$source')), findsOneWidget);
    final name = find.descendant(
      of: find.byKey(ValueKey('plan-name-$source')),
      matching: find.byType(EditableText),
    );
    await tester.enterText(name, '绝命毒师 - S01E01 - 新名称.mkv');
    await tester.pumpAndSettle();
    expect(
      container.read(organizerProvider).plan.first.targetName,
      '绝命毒师 - S01E01 - 新名称.mkv',
    );
    expect(file, findsOneWidget);

    await tester.enterText(name, 'invalid/name.mkv');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FButton>(find.byKey(const ValueKey('assistant-execute')))
          .onPress,
      isNull,
    );
    await tester.enterText(name, '绝命毒师 - S01E01 - 新名称.mkv');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FButton>(find.byKey(const ValueKey('assistant-execute')))
          .onPress,
      isNotNull,
    );

    await tester.tap(file);
    await tester.pumpAndSettle();
    final checkbox = find.byKey(ValueKey('plan-select-$source'));
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    expect(container.read(organizerProvider).plan.first.enabled, isFalse);
    expect(file, findsOneWidget);
    final tree = find.byKey(const ValueKey('assistant-plan-list'));
    expect(
      find.descendant(of: tree, matching: find.text('新建')),
      findsOneWidget,
    );
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    expect(
      container.read(organizerProvider).plan.every((p) => p.enabled),
      isTrue,
    );
    await tester.tap(find.text('全不选'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FButton>(find.byKey(const ValueKey('assistant-execute')))
          .onPress,
      isNull,
    );
    expect(find.descendant(of: tree, matching: find.text('新建')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('短目录名与新对话按钮靠对话区域右侧对齐', (tester) async {
    final (container, _) = await _pump(tester, 1280);
    container.read(assistantProvider.notifier).grantConsent();
    await container.read(assistantProvider.notifier).send('整理');
    await tester.pumpAndSettle();

    final directory = find.byKey(const ValueKey('assistant-directory'));
    final reset = find.byKey(const ValueKey('assistant-reset'));
    final messages = find.byKey(const ValueKey('assistant-messages'));
    expect(
      tester.getRect(reset).right,
      closeTo(tester.getRect(messages).right, .01),
    );
    expect(
      tester.getRect(reset).left - tester.getRect(directory).right,
      closeTo(8, .01),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('切换目录结构即时更新方案且不再次调用 AI', (tester) async {
    final (container, organizer) = await _pump(tester, 1280);
    container.read(assistantProvider.notifier).grantConsent();
    await container.read(assistantProvider.notifier).send('整理');
    await tester.pumpAndSettle();
    expect(find.text('Season 01'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('folder-layout-seasons')));
    await tester.pumpAndSettle();
    expect(organizer.proposals, 1);
    expect(find.text('绝命毒师 (2008)'), findsOneWidget);
    expect(find.text('Season 01'), findsNothing);
    expect(find.text('已调整目录结构。'), findsOneWidget);
    expect(find.text('整理方案 · 第 2 版'), findsWidgets);
    expect(find.text('新建 2 个文件夹'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('folder-layout-series')));
    await tester.tap(find.byKey(const ValueKey('folder-layout-movies')));
    await tester.pumpAndSettle();
    final plan = container.read(organizerProvider).plan;
    expect(plan.map((item) => item.targetDirectory), everyElement(isNull));
    expect(find.text('星际穿越 (2014)'), findsNothing);
    expect(container.read(assistantProvider).planVersion, 4);
    expect(tester.takeException(), isNull);
  });

  testWidgets('新要求生成的方案替换旧方案并支持发送与新对话', (tester) async {
    final (container, organizer) = await _pump(tester, 1280);
    container.read(assistantProvider.notifier).grantConsent();
    final input = find.descendant(
      of: find.byKey(const ValueKey('assistant-input')),
      matching: find.byType(EditableText),
    );
    expect(
      tester
          .widget<FButton>(find.byKey(const ValueKey('assistant-send')))
          .onPress,
      isNull,
    );
    await tester.enterText(input, '整理剧集');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('assistant-send')));
    await tester.pumpAndSettle();
    await tester.enterText(input, '电影保留年份');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(organizer.proposals, 2);
    expect(tester.widget<EditableText>(input).controller.text, isEmpty);
    expect(find.text('已按新要求更新整理方案。'), findsOneWidget);
    expect(find.text('已替换'), findsOneWidget);
    expect(find.text('整理方案 · 第 2 版'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('assistant-reset')));
    await tester.pumpAndSettle();
    expect(find.text('要怎么整理这个目录？'), findsOneWidget);
    expect(find.text('暂无整理方案'), findsOneWidget);
    expect(find.byKey(const ValueKey('assistant-plan-list')), findsNothing);
    expect(find.byKey(const ValueKey('assistant-execute')), findsNothing);
    expect(container.read(organizerProvider).plan, isEmpty);
    expect(container.read(organizerProvider).directory, _root);
    expect(tester.takeException(), isNull);
  });
}
