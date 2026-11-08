import 'package:azusa/app/theme.dart';
import 'package:azusa/core/settings/settings.dart';
import 'package:azusa/features/organizer/connections/connection_settings.dart';
import 'package:azusa/features/organizer/organizer_state.dart';
import 'package:azusa/features/organizer/scrape/scrape_dialog.dart';
import 'package:azusa/features/organizer/scrape/scrape_directory_picker.dart';
import 'package:azusa/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

const _config = ConnectionSettings(webdavUrl: 'https://nas.test/dav/');

class _Connections extends ConnectionSettingsController {
  @override
  Future<ConnectionSettings> build() async => _config;
}

class _Organizer extends OrganizerController {
  @override
  OrganizerState build() => const OrganizerState(
    directory: '/dav/',
    selectedDirectories: ['/dav/a/', '/dav/b/', '/dav/b/nested/'],
  );
}

Future<ProviderContainer> _mount(
  WidgetTester tester,
  Future<void> Function(BuildContext) open,
) async {
  final container = ProviderContainer(
    overrides: [
      organizerProvider.overrideWith(_Organizer.new),
      connectionSettingsProvider.overrideWith(_Connections.new),
      webDavFactoryProvider.overrideWithValue(
        (_) => throw StateError('Directory review must not access WebDAV'),
      ),
    ],
  );
  addTearDown(container.dispose);
  await container.read(connectionSettingsProvider.future);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...FLocalizations.localizationsDelegates,
        ],
        builder: (context, child) => FTheme(
          data: createAppTheme(
            const AppSettings(),
            brightness: Brightness.light,
            touch: true,
          ),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => open(context),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets(
    'dialog reuses page selection without browsing or changing browser state',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      List<String>? result;
      final container = await _mount(tester, (context) async {
        result = await showScrapeDirectoryPicker(context);
      });
      expect(
        find.byKey(const ValueKey('scrape-remove:/dav/a/')),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('scrape-remove:/dav/a/')),
      );
      await tester.tap(find.byKey(const ValueKey('scrape-remove:/dav/a/')));
      await tester.pumpAndSettle();
      final start = find.byKey(const ValueKey('scrape-start-scan'));
      expect(tester.widget<FButton>(start).onPress, isNotNull);
      expect(find.byKey(const ValueKey('scrape-picker-parent')), findsNothing);
      expect(
        find.byKey(const ValueKey('scrape-picker-add-current')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(start);
      await tester.pumpAndSettle();
      expect(result, ['/dav/b/', '/dav/b/nested/']);
      expect(container.read(organizerProvider).directory, '/dav/');
      expect(container.read(organizerProvider).selectedDirectories, [
        '/dav/a/',
        '/dav/b/',
        '/dav/b/nested/',
      ]);
      expect(() => result!.add('/dav/'), throwsUnsupportedError);
    },
  );

  for (final cleanup in [false, true]) {
    testWidgets(
      '${cleanup ? 'cleanup' : 'scrape'} waits for explicit directory confirmation before scanning',
      (tester) async {
        final container = await _mount(
          tester,
          cleanup ? showScrapeCleanupDialog : showScrapeDialog,
        );
        expect(find.byKey(const ValueKey('scrape-start-scan')), findsOneWidget);
        expect(container.read(organizerProvider).busy, isFalse);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('scrape-start-scan')), findsNothing);
        expect(container.read(organizerProvider).busy, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
