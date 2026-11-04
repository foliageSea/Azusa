import 'package:azusa/app/app.dart';
import 'package:azusa/app/router.dart';
import 'package:azusa/core/window/desktop_window.dart';
import 'package:azusa/features/organizer/connections/connection_settings.dart';
import 'package:azusa/features/organizer/connections/webdav_connections.dart';
import 'package:azusa/features/organizer/organizer_state.dart';
import 'package:azusa/features/organizer/startup_connection.dart';
import 'package:azusa/features/settings/settings_tab.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' show NoWindow, TestConnections, TestOrganizer;

class NoConnections extends ConnectionSettingsController {
  @override
  Future<ConnectionSettings> build() async => const ConnectionSettings();
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
  test('设置 Tab 标识和地址稳定，缺失及非法标识回退常规', () {
    for (final tab in SettingsTab.values) {
      expect(SettingsTab.fromParameter(tab.name), tab);
      expect(Uri.parse(tab.location).queryParameters['tab'], tab.name);
    }
    expect(SettingsTab.fromParameter(null), SettingsTab.general);
    expect(SettingsTab.fromParameter('invalid'), SettingsTab.general);
  });

  for (final width in [390.0, 1280.0]) {
    testWidgets('设置目标 Tab、缓存再次跳转、手动选择和返回导航 $width', (tester) async {
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
          startupConnectionProvider.overrideWith((ref) async {}),
          webDavConnectionsProvider.overrideWith(
            (ref) async => const [
              WebDavConnection(
                id: 'nas',
                name: 'NAS',
                url: 'https://nas.test/dav/',
              ),
            ],
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
      final router = container.read(routerProvider);

      router.go('/connections?tab=ai');
      await tester.pumpAndSettle();
      final aiField = find.byKey(const ValueKey('connection-field-3'));
      expect(aiField, findsOneWidget);
      final aiEditable = find.descendant(
        of: aiField,
        matching: find.byType(EditableText),
      );
      await tester.enterText(aiEditable, 'https://unsaved.test/v1');

      router.go('/connections?tab=tmdb');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('connection-field-6')), findsOneWidget);
      router.go('/connections?tab=ai');
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(aiEditable).controller.text,
        'https://unsaved.test/v1',
      );

      await tester.ensureVisible(find.text('HTTP 代理').first);
      await tester.tap(find.text('HTTP 代理').first);
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.queryParameters['tab'],
        'proxy',
      );
      router.push<void>('/connections?tab=about');
      await tester.pumpAndSettle();
      expect(find.text('MiSans 字体许可'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.queryParameters['tab'],
        'proxy',
      );
      expect(find.text('代理模式'), findsOneWidget);

      router.go('/settings?tab=tmdb&source=test');
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/connections');
      expect(
        router.routeInformationProvider.value.uri.queryParameters['source'],
        'test',
      );
      expect(find.byKey(const ValueKey('connection-field-6')), findsOneWidget);

      router.go('/organize');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('manage-webdav-connections')));
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.queryParameters['tab'],
        'webdav',
      );
      expect(
        find.byKey(const ValueKey('add-webdav-connection')),
        findsOneWidget,
      );

      for (final location in ['/connections?tab=invalid', '/connections']) {
        router.go(location);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('language-select')), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('未配置连接入口直接打开 WebDAV Tab', (tester) async {
    final window = NoWindow();
    addTearDown(window.dispose);
    final container = ProviderContainer(
      overrides: [
        desktopWindowProvider.overrideWithValue(window),
        connectionSettingsProvider.overrideWith(NoConnections.new),
        startupConnectionProvider.overrideWith((ref) async {}),
        webDavConnectionsProvider.overrideWith((ref) async => []),
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
    await tester.tap(find.text('配置连接'));
    await tester.pumpAndSettle();
    expect(
      container
          .read(routerProvider)
          .routeInformationProvider
          .value
          .uri
          .queryParameters['tab'],
      'webdav',
    );
    expect(find.byKey(const ValueKey('add-webdav-connection')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
