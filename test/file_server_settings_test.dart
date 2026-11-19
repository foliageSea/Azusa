import 'package:azusa/app/theme.dart';
import 'package:azusa/core/database/app_database.dart';
import 'package:azusa/core/settings/settings.dart';
import 'package:azusa/features/organizer/connections/connection_settings.dart';
import 'package:azusa/features/organizer/connections/connections_page.dart';
import 'package:azusa/features/organizer/connections/file_server_connections.dart';
import 'package:azusa/features/organizer/connections/webdav_connections.dart';
import 'package:azusa/features/organizer/connections/webdav_manager.dart';
import 'package:azusa/features/organizer/file_server/file_server.dart';
import 'package:azusa/features/organizer/file_server/file_server_connection.dart';
import 'package:azusa/features/organizer/file_server/file_server_factory.dart';
import 'package:azusa/features/organizer/organizer_state.dart';
import 'package:azusa/features/organizer/smb/smb_connection.dart';
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

const _smb = SmbConnection(
  id: 'smb',
  name: 'Media SMB',
  host: 'samba.example.test',
  share: 'Library',
  domain: 'WORKGROUP',
  username: 'viewer',
);

class _Repository extends FileServerConnectionsRepository {
  _Repository()
    : super(
        AppDatabase(open: () async => throw StateError('Unexpected DB')),
        const FlutterSecureStorage(),
      );

  int lookups = 0;
  @override
  Future<FileServerConnection> withPassword(FileServerConnection value) async {
    lookups++;
    if (value is SmbConnection) {
      return SmbConnection(
        id: value.id,
        name: value.name,
        host: value.host,
        share: value.share,
        domain: value.domain,
        username: value.username,
        password: 'stored secret',
      );
    }
    return value;
  }
}

class _Connections extends ConnectionSettingsController {
  _Connections(this.available);
  final List<FileServerConnection> available;
  final saved = <FileServerConnection>[];
  final selected = <String>[];

  @override
  Future<ConnectionSettings> build() async => const ConnectionSettings(
    fileServerConnection: _connection,
    proxyMode: ProxyMode.manual,
    proxyUrl: 'http://proxy.test:3128',
  );

  @override
  Future<void> saveConnection(FileServerConnection value) async {
    saved.add(value);
  }

  @override
  Future<void> selectConnection(String id) async {
    selected.add(id);
    state = AsyncData(
      state.requireValue.copyWith(
        fileServerConnection: available.singleWhere((item) => item.id == id),
      ),
    );
  }
}

class _Organizer extends OrganizerController {
  @override
  OrganizerState build() => const OrganizerState();

  void lock() => state = const OrganizerState(executing: true);
  void unlock() => state = const OrganizerState();
}

class _TestClient extends FileServerClient {
  bool closed = false;
  final listed = <String>[];

  @override
  String get root => '/';

  @override
  Future<List<FileServerEntry>> list(String path) async {
    listed.add(path);
    return [];
  }

  @override
  void close() => closed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_Connections> _mount(
  WidgetTester tester, {
  required String location,
  required Locale locale,
  List<FileServerConnection> connections = const [],
  _Repository? repository,
  _Organizer? organizer,
  FileServerClient Function(ConnectionSettings)? client,
}) async {
  final controller = _Connections(connections);
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: '/browser',
        builder: (context, state) => const Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: WebDavManager(compact: true),
          ),
        ),
      ),
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
        organizerProvider.overrideWith(() => organizer ?? _Organizer()),
        connectionSettingsProvider.overrideWith(() => controller),
        fileServerConnectionsProvider.overrideWith((ref) async => connections),
        if (repository != null)
          fileServerConnectionsRepositoryProvider.overrideWithValue(repository),
        if (client != null) fileServerClientProvider.overrideWithValue(client),
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
          child: FToaster(child: child!),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder _field(String key) => find.descendant(
  of: find.byKey(ValueKey(key)),
  matching: find.byType(EditableText),
);

Future<void> _enter(WidgetTester tester, String key, String text) async {
  final field = _field(key);
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, text);
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

  testWidgets(
    'SMB add validates native host and share, tests root, and saves',
    (tester) async {
      final tested = <ConnectionSettings>[];
      final server = _TestClient();
      final controller = await _mount(
        tester,
        location: SettingsTab.fileServers.location,
        locale: const Locale('en'),
        client: (settings) {
          tested.add(settings);
          return server;
        },
      );
      await _tap(tester, find.byKey(const ValueKey('add-webdav-connection')));
      final type = _field('file-server-type');
      await _tap(tester, type);
      await _tap(
        tester,
        find.byKey(const ValueKey('file-server-type-option-smb')),
      );
      expect(find.text('WebDAV URL'), findsNothing);
      expect(find.byType(FCheckbox), findsNothing);
      expect(find.byKey(const ValueKey('smb-editor-domain')), findsOneWidget);

      await _enter(tester, 'webdav-editor-field-0', ' New SMB ');
      await _enter(tester, 'smb-editor-host', 'smb://samba.example.test:445');
      await _enter(tester, 'smb-editor-share', 'Library');
      await _enter(tester, 'webdav-editor-field-2', 'viewer');
      await _tap(tester, find.text('Test'));
      expect(tested, isEmpty);
      expect(
        find.text(
          'Enter a DNS name or IPv4 address without a scheme, path, or port.',
        ),
        findsOneWidget,
      );

      await _enter(tester, 'smb-editor-host', ' samba.example.test ');
      await _enter(tester, 'smb-editor-share', 'Library/Movies');
      await _tap(tester, find.text('Save'));
      expect(controller.saved, isEmpty);
      expect(
        find.text('Enter a valid share name, not a path.'),
        findsOneWidget,
      );

      await _enter(tester, 'smb-editor-share', ' Library ');
      await _enter(tester, 'webdav-editor-password', ' secret ');
      await _tap(tester, find.text('Test'));
      expect(tested.single.proxyMode, ProxyMode.manual);
      final testedConnection =
          tested.single.fileServerConnection! as SmbConnection;
      expect(testedConnection.host, 'samba.example.test');
      expect(testedConnection.share, 'Library');
      expect(testedConnection.domain, isEmpty);
      expect(server.listed, ['/']);
      expect(server.closed, isTrue);
      expect(controller.saved, isEmpty);
      expect(find.byKey(_editorKey), findsOneWidget);

      await _tap(tester, find.text('Save'));
      final saved = controller.saved.single as SmbConnection;
      expect(saved.name, 'New SMB');
      expect(saved.username, 'viewer');
      expect(saved.password, ' secret ');
      expect(find.byKey(_editorKey), findsNothing);
    },
  );

  testWidgets('mixed settings show SMB address and keep its edit protocol', (
    tester,
  ) async {
    final repository = _Repository();
    final controller = await _mount(
      tester,
      location: SettingsTab.fileServers.location,
      locale: const Locale('en'),
      connections: const [_connection, _smb],
      repository: repository,
    );
    expect(find.widgetWithText(FBadge, 'WebDAV'), findsOneWidget);
    expect(find.widgetWithText(FBadge, 'SMB'), findsOneWidget);
    expect(find.text(_smb.displayAddress), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('webdav-menu-smb')));
    await _tap(tester, find.text('Edit'));
    expect(repository.lookups, 1);
    expect(
      tester.widget<EditableText>(_field('file-server-type')).controller.text,
      'SMB',
    );
    await tester.tap(_field('file-server-type'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('file-server-type-option-webdav')),
      findsNothing,
    );
    expect(
      tester.widget<EditableText>(_field('smb-editor-domain')).controller.text,
      'WORKGROUP',
    );
    await _enter(tester, 'webdav-editor-field-0', 'Renamed SMB');
    await _tap(tester, find.text('Save'));
    final saved = controller.saved.single as SmbConnection;
    expect(saved.id, _smb.id);
    expect(saved.name, 'Renamed SMB');
    expect(saved.share, _smb.share);
    expect(saved.password, 'stored secret');
  });

  testWidgets('saved SMB test uses its stored credentials, not active WebDAV', (
    tester,
  ) async {
    final repository = _Repository();
    final server = _TestClient();
    final tested = <ConnectionSettings>[];
    await _mount(
      tester,
      location: SettingsTab.fileServers.location,
      locale: const Locale('en'),
      connections: const [_connection, _smb],
      repository: repository,
      client: (settings) {
        tested.add(settings);
        return server;
      },
    );
    await _tap(tester, find.byKey(const ValueKey('webdav-menu-smb')));
    await _tap(tester, find.text('Test'));
    expect(repository.lookups, 1);
    final connection = tested.single.fileServerConnection! as SmbConnection;
    expect(connection.id, _smb.id);
    expect(connection.password, 'stored secret');
    expect(server.listed, ['/']);
    expect(server.closed, isTrue);
  });

  testWidgets('switcher search finds an SMB share by address', (tester) async {
    await _mount(
      tester,
      location: '/browser',
      locale: const Locale('en'),
      connections: [
        _connection,
        _smb,
        for (var index = 0; index < 5; index++)
          WebDavConnection(
            id: 'other-$index',
            name: 'Other $index',
            url: 'https://other-$index.test/dav/',
          ),
      ],
    );
    await _tap(tester, find.byKey(const ValueKey('webdav-switcher-trigger')));
    await _enter(tester, 'webdav-switcher-search', 'library');
    expect(
      find.byKey(const ValueKey('webdav-switcher-item-smb')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('webdav-switcher-item-nas')),
      findsNothing,
    );
  });

  for (final width in [410.0, 800.0]) {
    testWidgets(
      'mixed switcher honors organizer lock and navigation at $width',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 793));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final organizer = _Organizer();
        final controller = await _mount(
          tester,
          location: '/browser',
          locale: const Locale('en'),
          connections: const [_connection, _smb],
          organizer: organizer,
        );
        final trigger = find.byKey(const ValueKey('webdav-switcher-trigger'));
        final smb = find.byKey(const ValueKey('webdav-switcher-item-smb'));
        final manage = find.byKey(const ValueKey('manage-webdav-connections'));
        await _tap(tester, trigger);
        expect(find.text('SMB · ${_smb.displayAddress}'), findsOneWidget);
        expect(find.text('WebDAV · nas.test'), findsOneWidget);
        organizer.lock();
        await tester.pumpAndSettle();
        expect(tester.widget<FItem>(smb).onPress, isNull);
        expect(tester.widget<FItem>(manage).onPress, isNull);
        organizer.unlock();
        await tester.pumpAndSettle();
        await _tap(tester, smb);
        expect(controller.selected, [_smb.id]);
        expect(
          find.descendant(of: trigger, matching: find.text(_smb.name)),
          findsWidgets,
        );
        await _tap(tester, trigger);
        await _tap(tester, manage);
        expect(
          find.byKey(const ValueKey('add-webdav-connection')),
          findsOneWidget,
        );
        expect(find.widgetWithText(FBadge, 'SMB'), findsOneWidget);
      },
    );
  }
}
