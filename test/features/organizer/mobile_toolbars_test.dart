import 'package:azusa/app/theme.dart';
import 'package:azusa/core/settings/settings.dart';
import 'package:azusa/features/organizer/ai/ai_usage_history.dart';
import 'package:azusa/features/organizer/ai/ai_usage_page.dart';
import 'package:azusa/features/organizer/connections/connection_settings.dart';
import 'package:azusa/features/organizer/connections/webdav_connections.dart';
import 'package:azusa/features/organizer/dav/directory_favorites.dart';
import 'package:azusa/features/organizer/organizer_page.dart';
import 'package:azusa/features/organizer/organizer_state.dart';
import 'package:azusa/l10n/generated/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

const _connection = ConnectionSettings(
  connectionId: 'local',
  webdavUrl: 'https://example.com/dav/',
);

class _Connections extends ConnectionSettingsController {
  @override
  Future<ConnectionSettings> build() async => _connection;
}

class _Organizer extends OrganizerController {
  _Organizer({this.locked = false});
  final bool locked;
  bool scanned = false;

  @override
  OrganizerState build() => OrganizerState(directory: '/dav/', busy: locked);

  @override
  Future<List<String>> scanEmptyDirectories() async {
    scanned = true;
    return [];
  }
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required Widget page,
  required double width,
  double height = 1000,
  Locale locale = const Locale('zh'),
  double scale = 1,
  bool touch = false,
  _Organizer? organizer,
  VoidCallback? onUsageLoad,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final theme = createAppTheme(
    const AppSettings(),
    brightness: Brightness.light,
    touch: touch,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        aiUsageHistoryProvider.overrideWith((ref) async {
          onUsageLoad?.call();
          return [];
        }),
        connectionSettingsProvider.overrideWith(_Connections.new),
        organizerProvider.overrideWith(() => organizer ?? _Organizer()),
        webDavConnectionsProvider.overrideWith(
          (ref) async => const [
            WebDavConnection(
              id: 'local',
              name: 'local',
              url: 'https://example.com/dav/',
              username: '',
            ),
          ],
        ),
        directoryFavoritesProvider(nasScope(_connection))
            .overrideWith((ref) async => []),
      ],
      child: MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...FLocalizations.localizationsDelegates,
        ],
        theme: theme.toApproximateMaterialTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: FTheme(
            data: theme,
            child: FTooltipGroup(child: child!),
          ),
        ),
        home: Scaffold(body: page),
      ),
    ),
  );
  if (organizer?.locked ?? false) {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  } else {
    await tester.pumpAndSettle();
  }
}

void main() {
  for (final touch in [false, true]) {
    testWidgets('mobile file toolbar stays on one row (touch: $touch)', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        page: const OrganizerPage(),
        width: 375,
        touch: touch,
      );
      final connection = tester.getRect(
        find.byKey(const ValueKey('webdav-switcher-trigger')),
      );
      final sort = tester.getRect(find.byKey(const ValueKey('directory-sort')));
      final more = tester.getRect(
        find.byKey(const ValueKey('nas-browser-actions')),
      );
      expect(sort.center.dy, closeTo(connection.center.dy, 1));
      expect(more.center.dy, closeTo(sort.center.dy, 1));
      expect(find.text('清理空目录'), findsNothing);
      expect(find.text('断开连接'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('nas-browser-actions')));
      await tester.pumpAndSettle();
      expect(find.text('清理空目录'), findsOneWidget);
      expect(find.text('断开连接'), findsOneWidget);
      await tester.tap(find.text('断开连接'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nas-browser-actions')), findsNothing);
      expect(
        find.byKey(const ValueKey('nas-connection-toggle')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('mobile cleanup menu opens the existing dialog', (tester) async {
    final organizer = _Organizer();
    await _pumpPage(
      tester,
      page: const OrganizerPage(),
      width: 375,
      organizer: organizer,
    );
    await tester.tap(find.byKey(const ValueKey('nas-browser-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清理空目录'));
    await tester.pumpAndSettle();
    expect(organizer.scanned, isTrue);
    expect(find.byType(FDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile file actions are disabled while busy', (tester) async {
    await _pumpPage(
      tester,
      page: const OrganizerPage(),
      width: 375,
      organizer: _Organizer(locked: true),
    );
    final button = tester.widget<FButton>(
      find.byKey(const ValueKey('nas-browser-actions')),
    );
    expect(button.onPress, isNull);
    expect(tester.takeException(), isNull);
  });

  for (final locale in [const Locale('zh'), const Locale('en')]) {
    for (final width in [320.0, 375.0, 424.0, 1024.0]) {
      testWidgets('usage filters at $width in ${locale.languageCode}', (
        tester,
      ) async {
        var loads = 0;
        await _pumpPage(
          tester,
          page: const AiUsagePage(),
          width: width,
          locale: locale,
          onUsageLoad: () => loads++,
        );
        final model = tester.getRect(
          find.byKey(const ValueKey('usage-model-filter')),
        );
        final status = tester.getRect(
          find.byKey(const ValueKey('usage-status-filter')),
        );
        if (width < 600) {
          final periods = tester.getRect(
            find.byKey(const ValueKey('usage-periods')),
          );
          expect(model.top, greaterThan(periods.bottom));
          if (width >= 375) {
            expect(model.top, status.top);
            expect(model.width, greaterThan(status.width));
          } else {
            expect(status.top, greaterThan(model.bottom));
          }
          expect(
            tester
                .widget<FButton>(find.byKey(const ValueKey('usage-refresh')))
                .semanticsLabel,
            locale.languageCode == 'zh' ? '刷新用量' : 'Refresh usage',
          );
        } else {
          expect(
            find.text('Refresh usage'),
            locale.languageCode == 'en' ? findsOneWidget : findsNothing,
          );
        }
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('usage-refresh')));
        await tester.pumpAndSettle();
        expect(loads, 2);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('usage choices stack with large text', (tester) async {
    await _pumpPage(
      tester,
      page: const AiUsagePage(),
      width: 424,
      scale: 1.5,
      touch: true,
    );
    final model = tester.getRect(
      find.byKey(const ValueKey('usage-model-filter')),
    );
    final status = tester.getRect(
      find.byKey(const ValueKey('usage-status-filter')),
    );
    expect(status.top, greaterThan(model.bottom));
    expect(tester.takeException(), isNull);
  });

  for (final width in [375.0, 1024.0, 1600.0]) {
    testWidgets('usage filters stay fixed while content scrolls at $width', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        page: const AiUsagePage(),
        width: width,
        height: 500,
      );
      final filters = find.byKey(const ValueKey('usage-fixed-filters'));
      final before = tester.getRect(filters);
      final scrollable = find
          .descendant(
            of: find.byKey(const ValueKey('usage-scroll-content')),
            matching: find.byType(Scrollable),
          )
          .first;
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(position.maxScrollExtent, greaterThan(0));
      await tester.drag(scrollable, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(0));
      expect(tester.getRect(filters), before);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('desktop keeps visible file actions', (tester) async {
    await _pumpPage(tester, page: const OrganizerPage(), width: 1024);
    expect(find.text('清理空目录'), findsOneWidget);
    expect(find.text('断开连接'), findsOneWidget);
    expect(find.byKey(const ValueKey('nas-browser-actions')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
