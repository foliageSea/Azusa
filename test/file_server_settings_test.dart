import 'package:azusa/app/theme.dart';
import 'package:azusa/core/database/app_database.dart';
import 'package:azusa/core/settings/settings.dart';
import 'package:azusa/features/organizer/connections/connection_settings.dart';
import 'package:azusa/features/organizer/connections/connections_page.dart';
import 'package:azusa/features/organizer/connections/webdav_connections.dart';
import 'package:azusa/features/organizer/organizer_state.dart';
import 'package:azusa/features/settings/settings_tab.dart';
import 'package:azusa/l10n/generated/app_localizations.dart';
import 'package:azusa/shared/icon_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

const _typeFieldKey = ValueKey('file-server-type');
const _editorKey = ValueKey('webdav-editor-content');

const _connection = WebDavConnection(
  id: 'nas',
  name: 'My NAS',
  url: 'https://nas.test/dav/',
);

class _Repository extends WebDavConnectionsRepository {
  _Repository()
    : super(
        AppDatabase(open: () async => throw StateError('Unexpected DB')),
        const FlutterSecureStorage(),
      );

  int lookups = 0;
  @override
  Future<WebDavConnection> withPassword(WebDavConnection value) async {
    lookups++;
    return value;
  }
}

class _Connections extends ConnectionSettingsController {
  @override
  Future<ConnectionSettings> build() async => const ConnectionSettings();
}

class _Organizer extends OrganizerController {
  @override
  OrganizerState build() => const OrganizerState();
}

Future<void> _mount(
  WidgetTester tester, {
  required String location,
  required Locale locale,
  List<WebDavConnection> connections = const [],
  _Repository? repository,
}) async {
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: '/connections',
        builder: (context, state) => Scaffold(
          body: ConnectionsPage(
            tab: SettingsTab.fromParameter(state.uri.queryParameters['tab']),
          ),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        organizerProvider.overrideWith(_Organizer.new),
        connectionSettingsProvider.overrideWith(_Connections.new),
        webDavConnectionsProvider.overrideWith((ref) async => connections),
        if (repository != null)
          webDavConnectionsRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          ...AppLocalizations.localizationsDelegates,
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
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('legacy WebDAV URL opens English File Servers and its editor', (
    tester,
  ) async {
    await _mount(
      tester,
      location: '/connections?tab=webdav',
      locale: const Locale('en'),
    );

    expect(find.text('File Servers'), findsNWidgets(2));
    expect(find.text('No file servers configured.'), findsOneWidget);
    const addKey = ValueKey('add-webdav-connection');
    final add = find.byKey(addKey);
    expect(tester.widget<IconAction>(add).label, 'Add file server');
    expect(find.text('Add file server'), findsNothing);
    await tester.tap(add);
    await tester.pumpAndSettle();

    final editor = find.byKey(_editorKey);
    final type = find.byKey(_typeFieldKey);
    expect(editor, findsOneWidget);
    expect(
      find.descendant(of: type, matching: find.text('File server type')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: type, matching: find.text('WebDAV')),
      findsOneWidget,
    );
    expect(find.text('WebDAV URL'), findsOneWidget);
    await tester.tap(
      find.descendant(of: type, matching: find.byType(EditableText)),
    );
    await tester.pumpAndSettle();
    final option = find.byKey(const ValueKey('file-server-type-option-webdav'));
    expect(option, findsOneWidget);
    await tester.tap(
      find.descendant(of: type, matching: find.byType(EditableText)),
    );
    await tester.pumpAndSettle();
    expect(option, findsNothing);
    expect(
      find.byKey(const ValueKey('webdav-editor-password')),
      findsOneWidget,
    );
    final cancel = find.text('Cancel');
    await tester.ensureVisible(cancel);
    await tester.pumpAndSettle();
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(editor, findsNothing);
  });

  testWidgets('Chinese narrow settings still show the WebDAV protocol', (
    tester,
  ) async {
    final repository = _Repository();
    await tester.binding.setSurfaceSize(const Size(410, 793));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _mount(
      tester,
      location: SettingsTab.fileServers.location,
      locale: const Locale('zh'),
      connections: const [_connection],
      repository: repository,
    );

    expect(SettingsTab.fileServers.location, '/connections?tab=fileServers');
    expect(find.text('文件服务器'), findsNWidgets(2));
    expect(find.text('添加文件服务器'), findsNothing);
    expect(find.widgetWithText(FBadge, 'WebDAV'), findsOneWidget);
    expect(find.text('My NAS'), findsOneWidget);
    expect(find.text('尚未配置文件服务器。'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('webdav-menu-nas')));
    await tester.pumpAndSettle();
    await tester.tap(find.text("编辑"));
    await tester.pumpAndSettle();
    expect(repository.lookups, 1);
    expect(find.byKey(_editorKey), findsOneWidget);
    expect(find.text('文件服务器类型'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(_typeFieldKey),
        matching: find.text('WebDAV'),
      ),
      findsOneWidget,
    );
    expect(find.text(_connection.name), findsWidgets);
    expect(find.text(_connection.url), findsWidgets);
  });
}
