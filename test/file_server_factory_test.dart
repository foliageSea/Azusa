import 'package:azusa/features/organizer/connections/connection_settings.dart';
import 'package:azusa/features/organizer/connections/webdav_connections.dart';
import 'package:azusa/features/organizer/dav/webdav.dart';
import 'package:azusa/features/organizer/file_server/file_server.dart';
import 'package:azusa/features/organizer/file_server/file_server_connection.dart';
import 'package:azusa/features/organizer/file_server/file_server_factory.dart';
import 'package:azusa/features/organizer/file_server/file_server_paths.dart';
import 'package:azusa/features/organizer/organizer_state.dart';
import 'package:azusa/features/organizer/startup_connection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'startup_connection_test.dart' show SavedConnections;

class _MemoryConnection implements FileServerConnection {
  const _MemoryConnection();

  @override
  String get id => 'memory-1';
  @override
  String get name => 'Memory';
  @override
  String get protocol => 'memory';
}

class _MemoryProtocol implements FileServerProtocol {
  final sessions = <_MemoryClient>[];
  bool fail = false;

  @override
  void validate(FileServerConnection connection) {
    if (connection is! _MemoryConnection) throw const FormatException();
  }

  @override
  FileServerScope scope(FileServerConnection connection) {
    validate(connection);
    return (
      endpoint: 'memory:${connection.id}',
      username: '',
      root: '/library/',
    );
  }

  @override
  FileServerClient create(
    FileServerConnection connection,
    ConnectionSettings settings,
  ) {
    final client = _MemoryClient(scope(connection).root, fail: fail);
    sessions.add(client);
    return client;
  }
}

class _MemoryClient extends FileServerClient {
  _MemoryClient(this.root, {required this.fail});

  @override
  final String root;
  final bool fail;
  bool closed = false;

  @override
  String normalize(String path) {
    final normalized = canonicalFileServerPath(path);
    if (!normalized.startsWith(root)) throw const FormatException();
    return normalized;
  }

  @override
  Future<List<FileServerEntry>> list(String path) async {
    if (fail) throw StateError('模拟文件服务器连接失败');
    return [FileServerEntry('${normalize(path)}movie.mkv', false)];
  }

  @override
  void close() => closed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'registering a non-WebDAV protocol supports startup and clears sessions',
    () async {
      const connection = _MemoryConnection();
      const settings = ConnectionSettings(fileServerConnection: connection);
      final memory = _MemoryProtocol();
      final container = ProviderContainer(
        overrides: [
          connectionSettingsProvider.overrideWith(
            () => SavedConnections(Future.value(settings)),
          ),
          fileServerFactoryProvider.overrideWithValue(
            FileServerFactory({'memory': memory}),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(startupConnectionProvider.future);
      final organizer = container.read(organizerProvider.notifier);
      expect(container.read(organizerProvider).directory, '/library/');
      expect(
        container.read(organizerProvider).entries.single.name,
        'movie.mkv',
      );
      expect(memory.sessions.single.closed, isTrue);

      memory.fail = true;
      await organizer.open(null);
      expect(container.read(organizerProvider).hasError, isTrue);
      expect(memory.sessions, hasLength(2));
      expect(memory.sessions.every((client) => client.closed), isTrue);
    },
  );

  test('WebDAV is the default adapter and unknown protocols are rejected', () {
    const connection = WebDavConnection(
      id: 'dav',
      name: 'Library',
      url: 'https://NAS.test/share%20files',
    );
    const factory = defaultFileServerFactory;
    expect(factory.root(connection), '/share%20files/');
    final client = factory.create(
      const ConnectionSettings(fileServerConnection: connection),
    );
    addTearDown(client.close);
    expect(client, isA<WebDavClient>());
    expect(client.root, factory.root(connection));
    expect(
      client.normalize('/share%20files/%E5%89%A7%25.mkv'),
      '/share%20files/%E5%89%A7%25.mkv',
    );
    expect(() => client.normalize('/other/'), throwsFormatException);
    expect(
      () => factory.validate(const _MemoryConnection()),
      throwsFormatException,
    );
    expect(
      () => factory.create(
        const ConnectionSettings(fileServerConnection: _MemoryConnection()),
      ),
      throwsFormatException,
    );
    expect(() => factory.create(const ConnectionSettings()), throwsStateError);
  });
}
