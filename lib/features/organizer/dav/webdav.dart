import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

import '../connections/connection_settings.dart';
import '../connections/http_clients.dart';
import '../connections/webdav_connections.dart';
import '../file_server/file_server.dart';
import '../file_server/file_server_paths.dart';

class WebDavClient extends FileServerClient {
  WebDavClient(ConnectionSettings settings, {Dio? client})
    : this.forConnection(_connectionFrom(settings), settings, client: client);

  WebDavClient.forConnection(
    this.connection,
    ConnectionSettings settings, {
    Dio? client,
  }) : base = endpoint(connection),
       dio =
           client ??
           createServiceClient(
             connection.apply(settings),
             service: NetworkService.webdav,
           );

  final WebDavConnection connection;
  final Dio dio;
  final Uri base;

  static WebDavConnection _connectionFrom(ConnectionSettings settings) {
    final connection = settings.fileServerConnection;
    if (connection is WebDavConnection) return connection;
    throw const FormatException('请输入有效的 HTTPS 地址（WebDAV 可使用 HTTP）');
  }

  static Uri endpoint(WebDavConnection connection) =>
      validatedHttpUrl(connection.url, allowHttp: true);

  static String rootFor(Uri uri) => canonicalFileServerPath(
    uri.path.endsWith('/') ? uri.path : '${uri.path}/',
  );

  @override
  String get root => rootFor(base);

  @override
  String normalize(String path) {
    final normalized = canonicalFileServerPath(path);
    if (!normalized.startsWith(root)) {
      throw const FormatException('路径不在 WebDAV 连接目录内');
    }
    return normalized;
  }

  Uri url(String path) => Uri.parse('${base.origin}${normalize(path)}');

  Options options({Map<String, String>? headers}) => Options(
    headers: {
      if (connection.username.isNotEmpty)
        'Authorization':
            'Basic ${base64Encode(utf8.encode('${connection.username}:${connection.password}'))}',
      ...?headers,
    },
    responseType: ResponseType.plain,
  );

  Future<List<FileServerEntry>> _properties(
    String path,
    String depth, {
    bool strict = false,
  }) async {
    final response = await dio.requestUri<String>(
      url(path),
      options: options(
        headers: {
          'Depth': depth,
          'Content-Type': 'application/xml; charset=utf-8',
        },
      ).copyWith(method: 'PROPFIND'),
      data: '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/><d:getetag/><d:getcontentlength/><d:getlastmodified/></d:prop></d:propfind>',
    );
    if (response.statusCode != 207) {
      throw const FormatException('WebDAV 未返回有效属性');
    }
    final document = XmlDocument.parse(response.data ?? '');
    final results = <FileServerEntry>[];
    for (final node in document.descendants.whereType<XmlElement>().where(
      (e) => e.name.local == 'response',
    )) {
      String? text(XmlElement e, String key) => e.descendants
          .whereType<XmlElement>()
          .where((v) => v.name.local == key)
          .firstOrNull
          ?.innerText;
      final href = text(node, 'href');
      if (href == null) {
        if (strict) throw const FormatException('WebDAV 未返回有效属性');
        continue;
      }
      final uri = url(path).resolve(href);
      if (uri.origin != base.origin) {
        if (strict) throw const FormatException('WebDAV 未返回有效属性');
        continue;
      }
      final successful = node.childElements
          .where((e) => e.name.local == 'propstat')
          .where(
            (e) =>
                RegExp(r'HTTP/\S+ 200(?: |$)')
                    .hasMatch(text(e, 'status') ?? ''),
          )
          .toList();
      if (successful.isEmpty) {
        if (strict) throw const FormatException('无法确定文件状态，请检查 WebDAV 权限');
        continue;
      }
      if (strict &&
          !successful.any(
            (s) => s.descendants.whereType<XmlElement>().any(
              (e) => e.name.local == 'resourcetype',
            ),
          )) {
        throw const FormatException('无法确定文件状态，请检查 WebDAV 权限');
      }
      final isDirectory = successful.any(
        (s) => s.descendants.whereType<XmlElement>().any(
          (e) => e.name.local == 'collection',
        ),
      );
      String? property(String key) =>
          successful.map((s) => text(s, key)).whereType<String>().firstOrNull;
      final entryPath = canonicalFileServerPath(uri.path);
      if (!entryPath.startsWith(root)) {
        if (strict) throw const FormatException('WebDAV 未返回有效属性');
        continue;
      }
      results.add(
        FileServerEntry(
          isDirectory && !entryPath.endsWith('/') ? '$entryPath/' : entryPath,
          isDirectory,
          versionToken: property('getetag'),
          size: int.tryParse(property('getcontentlength') ?? ''),
          modified: property('getlastmodified'),
        ),
      );
    }
    if (strict && !results.any((e) => e.path == path && e.directory)) {
      throw const FormatException('无法确定文件状态，请检查 WebDAV 权限');
    }
    return results;
  }

  @override
  Future<List<FileServerEntry>> list(String path) async {
    final results = await _listChildren(path, strict: false);
    return results
        .where(
          (e) =>
              !e.name.startsWith('.') &&
              !(e.directory && (e.name == '#recycle' || e.name == '__MACOSX')),
        )
        .toList();
  }

  /// Unfiltered immediate children. Required for safe empty-folder checks.
  @override
  Future<List<FileServerEntry>> listAll(String path) async {
    return _listChildren(path, strict: true);
  }

  Future<List<FileServerEntry>> _listChildren(
    String path, {
    required bool strict,
  }) async {
    final directory = normalize(path.endsWith('/') ? path : '$path/');
    final results = await _properties(directory, '1', strict: strict);
    if (strict &&
        results.any(
          (e) =>
              !e.path.startsWith(directory) ||
              (e.path != directory &&
                  e.path
                      .substring(directory.length)
                      .replaceFirst(RegExp(r'/$'), '')
                      .contains('/')),
        )) {
      throw const FormatException('WebDAV 未返回有效属性');
    }
    return results
        .where(
          (e) =>
              e.path != directory &&
              e.path.startsWith(directory) &&
              !e.path
                  .substring(directory.length)
                  .replaceFirst(RegExp(r'/$'), '')
                  .contains('/'),
        )
        .toList()
      ..sort(
        (a, b) => a.directory == b.directory
            ? a.name.compareTo(b.name)
            : a.directory
            ? -1
            : 1,
      );
  }

  @override
  Future<FileServerEntry?> stat(String path) async {
    try {
      final normalized = normalize(path);
      final properties = await _properties(normalized, '0');
      final entry = properties
          .where(
            (e) =>
                e.path.replaceFirst(RegExp(r'/$'), '') ==
                normalized.replaceFirst(RegExp(r'/$'), ''),
          )
          .firstOrNull;
      if (entry == null) throw const FormatException('无法确定文件状态，请检查 WebDAV 权限');
      return entry;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<void> move(String from, String to, {String? versionToken}) async {
    final response = await dio.requestUri<String>(
      url(from),
      options: options(
        headers: {
          'Destination': url(to).toString(),
          'Overwrite': 'F',
          if (versionToken != null && !versionToken.startsWith('W/'))
            'If-Match': versionToken,
        },
      ).copyWith(method: 'MOVE'),
    );
    if (![201, 204].contains(response.statusCode)) {
      throw const FormatException('移动未确认成功，请刷新目录核对');
    }
  }

  @override
  Future<void> mkdir(String path) async {
    final response = await dio.requestUri<String>(
      url(path.endsWith('/') ? path : '$path/'),
      options: options().copyWith(method: 'MKCOL'),
    );
    if (response.statusCode != 201) throw const FormatException('创建目录未确认成功');
  }

  @override
  Future<void> remove(String path) async {
    final response = await dio.deleteUri<String>(url(path), options: options());
    if (![200, 204].contains(response.statusCode)) {
      throw const FormatException('删除未确认成功，请刷新目录核对');
    }
  }

  @override
  Future<void> upload(String path, Stream<List<int>> bytes, int length) async {
    final response = await dio.putUri<String>(
      url(path),
      data: bytes,
      options: options(
        headers: {
          'Content-Type': 'application/octet-stream',
          'Content-Length': '$length',
          'If-None-Match': '*',
        },
      ),
    );
    if (response.statusCode != 201) {
      throw const FormatException('上传未确认成功，请刷新目录核对');
    }
  }

  @override
  Future<void> download(String path, String destination) async {
    await dio.downloadUri(url(path), destination, options: options());
  }

  @override
  void close() => dio.close(force: true);
}
