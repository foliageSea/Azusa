import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../connections/connection_settings.dart';
import '../connections/webdav_connections.dart';
import '../dav/webdav.dart';
import '../smb/smb_client.dart';
import '../smb/smb_connection.dart';
import 'file_server.dart';
import 'file_server_connection.dart';

/// One protocol's client factory and offline connection metadata.
abstract interface class FileServerProtocol {
  void validate(FileServerConnection connection);
  FileServerClient create(
    FileServerConnection connection,
    ConnectionSettings settings,
  );
  FileServerScope scope(FileServerConnection connection);
}

class FileServerFactory {
  const FileServerFactory(this.protocols);

  final Map<String, FileServerProtocol> protocols;

  FileServerProtocol _protocol(FileServerConnection connection) =>
      protocols[connection.protocol] ??
      (throw const FormatException('不支持此文件服务器协议'));

  void validate(FileServerConnection connection) =>
      _protocol(connection).validate(connection);

  FileServerClient create(ConnectionSettings settings) {
    final connection = settings.fileServerConnection;
    if (connection == null) throw StateError('未配置文件服务器连接');
    return _protocol(connection).create(connection, settings);
  }

  String root(FileServerConnection connection) => scope(connection).root;

  FileServerScope scope(FileServerConnection connection) =>
      _protocol(connection).scope(connection);
}

class _WebDavProtocol implements FileServerProtocol {
  const _WebDavProtocol();

  WebDavConnection _webDav(FileServerConnection connection) {
    if (connection is WebDavConnection) return connection;
    throw const FormatException('文件服务器连接配置无效');
  }

  @override
  void validate(FileServerConnection connection) => scope(connection);

  @override
  FileServerClient create(
    FileServerConnection connection,
    ConnectionSettings settings,
  ) => WebDavClient.forConnection(_webDav(connection), settings);

  @override
  FileServerScope scope(FileServerConnection connection) {
    final value = _webDav(connection);
    final uri = WebDavClient.endpoint(value);
    final root = WebDavClient.rootFor(uri);
    // Preserve existing favorites keys for WebDAV.
    return (
      endpoint: '${uri.origin}$root',
      username: value.username,
      root: root,
    );
  }
}

class _SmbProtocol implements FileServerProtocol {
  const _SmbProtocol();

  SmbConnection _smb(FileServerConnection connection) {
    if (connection is SmbConnection) return connection;
    throw const FormatException('文件服务器连接配置无效');
  }

  @override
  void validate(FileServerConnection connection) => _smb(connection).validate();

  @override
  FileServerClient create(
    FileServerConnection connection,
    ConnectionSettings settings,
  ) => SmbClient.forConnection(_smb(connection));

  @override
  FileServerScope scope(FileServerConnection connection) => _smb(connection).scope;
}

const defaultFileServerFactory = FileServerFactory({
  WebDavConnection.protocolId: _WebDavProtocol(),
  SmbConnection.protocolId: _SmbProtocol(),
});
final fileServerFactoryProvider = Provider<FileServerFactory>(
  (ref) => defaultFileServerFactory,
);
final fileServerClientProvider =
    Provider<FileServerClient Function(ConnectionSettings)>(
      (ref) => ref.watch(fileServerFactoryProvider).create,
    );
