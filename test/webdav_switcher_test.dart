import 'package:azusa/core/database/app_database.dart';
import 'package:azusa/features/organizer/connections/connection_settings.dart';
import 'package:azusa/features/organizer/connections/webdav_connections.dart';
import 'package:azusa/features/organizer/connections/webdav_manager.dart';
import 'package:azusa/features/organizer/organizer_state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:sqlite3/sqlite3.dart';

import 'webdav_connections_test.dart' show MemorySecrets;
import 'webdav_manager_test.dart' show app;
import 'webdav_switching_test.dart'
    show MemoryPreferences, SwitchingOrganizer, SwitchingDav;

void main() {
  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets('连接面板搜索、当前项、预览确认和操作锁 $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final database = AppDatabase(open: () async => sqlite3.openInMemory());
      addTearDown(database.close);
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          connectionRepositoryProvider.overrideWithValue(
            ConnectionRepository(MemoryPreferences(), MemorySecrets()),
          ),
          organizerProvider.overrideWith(SwitchingOrganizer.new),
          webDavFactoryProvider.overrideWithValue(
            (settings) => SwitchingDav(settings),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(connectionSettingsProvider.future);
      final repository = container.read(webDavConnectionsRepositoryProvider);
      for (var i = 0; i < 8; i++) {
        await repository.save(
          WebDavConnection(
            id: '$i',
            name: i == 0 ? 'Home NAS' : 'NAS $i',
            url: 'https://nas$i.test/dav/',
            password: 'password-$i',
          ),
          activate: i == 0,
        );
      }
      container.invalidate(connectionSettingsProvider);
      await container.read(connectionSettingsProvider.future);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: app(
            const Padding(
              padding: EdgeInsets.all(24),
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 280,
                  child: WebDavManager(compact: true),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final trigger = find.byKey(const ValueKey('webdav-switcher-trigger'));
      Future<void> open() async {
        await tester.tap(trigger);
        await tester.pumpAndSettle();
      }

      await open();
      expect(
        find.byKey(const ValueKey('webdav-switcher-panel')),
        findsOneWidget,
      );
      final panel = tester.getRect(
        find.byKey(const ValueKey('webdav-switcher-panel')),
      );
      expect(panel.left, greaterThanOrEqualTo(0));
      expect(panel.right, lessThanOrEqualTo(width));
      if (width < 600) expect(panel.bottom, closeTo(900, 1));
      final current = tester.widget<FItem>(
        find.byKey(const ValueKey('webdav-switcher-item-0')),
      );
      expect(current.semanticsChecked, isTrue);
      expect(find.text('nas0.test'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('webdav-switcher-item-0')));
      await tester.pumpAndSettle();
      expect(container.read(organizerProvider).plan, isNotEmpty);
      expect(find.byKey(const ValueKey('webdav-switcher-panel')), findsNothing);

      await open();
      final search = find.descendant(
        of: find.byKey(const ValueKey('webdav-switcher-search')),
        matching: find.byType(EditableText),
      );
      await tester.enterText(search, 'NAS7.TEST');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('webdav-switcher-item-0')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('webdav-switcher-item-7')),
        findsOneWidget,
      );
      await tester.enterText(search, 'no-match');
      await tester.pumpAndSettle();
      expect(find.text('未找到匹配的连接'), findsOneWidget);
      await tester.enterText(search, 'NAS 7');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('webdav-switcher-item-7')));
      await tester.pumpAndSettle();
      expect(find.text('放弃当前重命名预览并更换连接？'), findsOneWidget);
      expect(find.byKey(const ValueKey('webdav-switcher-panel')), findsNothing);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(await repository.activeId(), '0');
      await open();
      await tester.enterText(search, 'NAS 7');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('webdav-switcher-item-7')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(await repository.activeId(), '7');
      expect(container.read(organizerProvider).plan, isEmpty);
      expect(
        container.read(connectionSettingsProvider).requireValue.webdavPassword,
        'password-7',
      );

      await open();
      (container.read(organizerProvider.notifier) as SwitchingOrganizer).lock();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FItem>(find.byKey(const ValueKey('webdav-switcher-item-0')))
            .onPress,
        isNull,
      );
      expect(
        tester
            .widget<FItem>(
              find.byKey(const ValueKey('manage-webdav-connections')),
            )
            .onPress,
        isNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await database.close();
    });
  }
}
