import 'package:azusa/core/database/app_database.dart';
import 'package:azusa/app/theme.dart';
import 'package:azusa/core/settings/settings.dart';
import 'package:azusa/l10n/generated/app_localizations.dart';
import 'package:azusa/features/organizer/connections/connection_settings.dart';
import 'package:azusa/features/organizer/connections/webdav_connections.dart';
import 'package:azusa/features/organizer/connections/webdav_manager.dart';
import 'package:azusa/features/organizer/organizer_state.dart';
import 'package:azusa/features/organizer/organizer_page.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:sqlite3/sqlite3.dart';

import 'webdav_connections_test.dart' show MemorySecrets;
import 'webdav_switching_test.dart'
    show MemoryPreferences, SwitchingDav, SwitchingOrganizer;

Widget app(
  Widget child, {
  String language = 'zh',
  Brightness brightness = Brightness.light,
}) => MaterialApp(
  locale: Locale(language),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    ...FLocalizations.localizationsDelegates,
  ],
  builder: (context, child) => FTheme(
    data: createAppTheme(
      const AppSettings(),
      brightness: brightness,
      touch: false,
    ),
    child: FToaster(child: child!),
  ),
  home: Scaffold(body: child),
);

void main() {
  for (final width in [320.0, 390.0, 800.0, 1280.0]) {
    for (final language in ['zh', 'en']) {
      testWidgets('连接工具栏与多连接列表在 $width / $language 下无溢出', (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final database = AppDatabase(open: () async => sqlite3.openInMemory());
        addTearDown(database.close);
        final preferences = MemoryPreferences();
        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(database),
            connectionRepositoryProvider.overrideWithValue(
              ConnectionRepository(preferences, MemorySecrets()),
            ),
            organizerProvider.overrideWith(SwitchingOrganizer.new),
          ],
        );
        addTearDown(container.dispose);
        await container.read(connectionSettingsProvider.future);
        final repository = container.read(webDavConnectionsRepositoryProvider);
        final longName = List.filled(12, '家庭 NAS server').join(' ');
        await repository.save(
          WebDavConnection(
            id: 'one',
            name: longName,
            url: 'https://nas.test/very/long/path/dav/',
          ),
        );
        await repository.save(
          WebDavConnection(
            id: 'two',
            name: 'Other NAS',
            url: 'https://other.test/dav/',
          ),
          activate: true,
        );
        container.invalidate(connectionSettingsProvider);
        await container.read(connectionSettingsProvider.future);
        Widget page(Widget child) => UncontrolledProviderScope(
          container: container,
          child: app(
            child,
            language: language,
            brightness: language == 'en' ? Brightness.dark : Brightness.light,
          ),
        );
        await tester.pumpWidget(
          page(
            const SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: WebDavManager(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(FBadge), findsOneWidget);
        expect(
          find.byKey(const ValueKey('webdav-connection-select')),
          findsNothing,
        );
        final add = tester.getSize(
          find.byKey(const ValueKey('add-webdav-connection')),
        );
        expect(add.width, lessThan(width - 48));
        final rowMenu = tester.getRect(
          find.byKey(const ValueKey('webdav-menu-one')),
        );
        final use = tester.getRect(
          find.byKey(const ValueKey('use-webdav-one')),
        );
        if (width < 500) expect(use.top, greaterThanOrEqualTo(rowMenu.bottom));
        expect(tester.takeException(), isNull);

        await tester.tap(find.byKey(const ValueKey('add-webdav-connection')));
        await tester.pumpAndSettle();
        final expectedHints = language == 'zh'
            ? ['请输入连接名称', '请输入 WebDAV 地址', '请输入用户名', '请输入密码']
            : [
                'Enter a connection name',
                'Enter a WebDAV URL',
                'Enter a username',
                'Enter a password',
              ];
        for (var i = 0; i < 4; i++) {
          final key = i == 3
              ? 'webdav-editor-password'
              : 'webdav-editor-field-$i';
          expect(
            tester.widget<FTextField>(find.byKey(ValueKey(key))).hint,
            expectedHints[i],
          );
          expect(find.text(expectedHints[i]), findsOneWidget);
        }
        final dialog = tester.getRect(
          find.byKey(const ValueKey('webdav-editor-content')),
        );
        expect(dialog.width, lessThanOrEqualTo(480));
        expect(dialog.left, greaterThanOrEqualTo(0));
        expect(dialog.right, lessThanOrEqualTo(width));
        expect(tester.takeException(), isNull);
        await tester.tap(find.text(language == 'zh' ? '取消' : 'Cancel'));
        await tester.pumpAndSettle();

        await tester.pumpWidget(page(const OrganizerPage()));
        await tester.pumpAndSettle();
        final selector = find.byKey(const ValueKey('webdav-connection-select'));
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('nas-browser')),
            matching: selector,
          ),
          findsOneWidget,
        );
        expect(tester.getSize(selector).width, lessThanOrEqualTo(280));
        expect(
          find.byKey(const ValueKey('manage-webdav-connections')),
          findsOneWidget,
        );
        final sort = tester.getRect(
          find.byKey(const ValueKey('directory-sort')),
        );
        final select = tester.getRect(selector);
        if (width < 600) {
          expect(sort.top, greaterThanOrEqualTo(select.bottom));
        } else {
          expect(sort.left, greaterThan(select.right));
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await database.close();
      });
    }
  }
  for (final width in [320.0, 1280.0]) {
    testWidgets('WebDAV 新增编辑、密码显隐、切换确认和删除在 $width 宽度可用', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final database = AppDatabase(open: () async => sqlite3.openInMemory());
      addTearDown(database.close);
      final secrets = MemorySecrets();
      final preferences = MemoryPreferences();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          connectionRepositoryProvider.overrideWithValue(
            ConnectionRepository(preferences, secrets),
          ),
          organizerProvider.overrideWith(SwitchingOrganizer.new),
          webDavFactoryProvider.overrideWithValue(
            (settings) => SwitchingDav(settings),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(connectionSettingsProvider.future);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: app(const SingleChildScrollView(child: WebDavManager())),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add-webdav-connection')));
      await tester.pumpAndSettle();
      Finder editable(String key) => find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(EditableText),
      );
      await tester.enterText(editable('webdav-editor-field-0'), 'My NAS');
      await tester.enterText(
        editable('webdav-editor-field-1'),
        'https://nas.test/dav/',
      );
      await tester.enterText(editable('webdav-editor-field-2'), 'user');
      await tester.enterText(editable('webdav-editor-password'), 'password');
      expect(
        tester
            .widget<EditableText>(editable('webdav-editor-password'))
            .obscureText,
        isTrue,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('webdav-editor-toggle-password')),
      );
      await tester.tap(
        find.byKey(const ValueKey('webdav-editor-toggle-password')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(editable('webdav-editor-password'))
            .obscureText,
        isFalse,
      );
      await tester.ensureVisible(find.text('保存'));
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      final repository = container.read(webDavConnectionsRepositoryProvider);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      final saved = (await repository.load()).single;
      await tester.pumpAndSettle();
      expect(saved.password, 'password');
      expect(find.text('My NAS'), findsWidgets);
      expect(
        find.byKey(const ValueKey('webdav-editor-password')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(ValueKey('webdav-menu-${saved.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(editable('webdav-editor-password'))
            .obscureText,
        isTrue,
      );
      await tester.enterText(editable('webdav-editor-field-0'), 'Updated NAS');
      await tester.ensureVisible(find.text('保存'));
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect((await repository.load()).single.name, 'Updated NAS');
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('webdav-connection-select')),
        findsNothing,
      );
      final use = find.byKey(ValueKey('use-webdav-${saved.id}'));
      await tester.tap(use);
      await tester.pumpAndSettle();
      expect(find.text('放弃当前重命名预览并更换连接？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(await repository.activeId(), isNull);
      await tester.tap(use);
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(await repository.activeId(), saved.id);
      expect(container.read(organizerProvider).plan, isEmpty);

      await tester.tap(find.byKey(ValueKey('webdav-menu-${saved.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(await repository.load(), isEmpty);
      expect(await repository.activeId(), isNull);
      expect(secrets.values, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await database.close();
    });
  }
}
