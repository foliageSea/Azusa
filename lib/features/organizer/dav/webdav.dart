import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

import '../connections/connection_settings.dart';
import 'dav_paths.dart';
import '../connections/http_clients.dart';

class DavEntry {
  const DavEntry(
    this.path,
    this.directory, {
    this.etag,
    this.size,
    this.modified,
  });
  final String path;
  final bool directory;
  final String? etag, modified;
  final int? size;
  String get name =>
      Uri.decodeComponent(path.split('/').where((s) => s.isNotEmpty).last);
  String? get fingerprint =>
      etag ?? (size == null && modified == null ? null : '$size:$modified');
}

class WebDavClient {
  WebDavClient(this.settings, {Dio? client})
    : base = validatedHttpUrl(settings.webdavUrl, allowHttp: true),
      dio =
          client ??
          createServiceClient(settings, service: NetworkService.webdav) {
    if (base.query.isNotEmpty || base.fragment.isNotEmpty) {
      throw const FormatException('WebDAV 地址不能包含参数');
    }
  }
  final ConnectionSettings settings;
  final Dio dio;
  final Uri base;

  String get root =>
      canonicalDavPath(base.path.endsWith('/') ? base.path : '${base.path}/');

  String normalize(String path) {
    final normalized = canonicalDavPath(path);
    if (!normalized.startsWith(root)) {
      throw const FormatException('路径不在 WebDAV 连接目录内');
    }
    return normalized;
  }

  Uri url(String path) => Uri.parse('${base.origin}${normalize(path)}');

  Options options({Map<String, String>? headers}) => Options(
    headers: {
      if (settings.username.isNotEmpty)
        'Authorization':
            'Basic ${base64Encode(utf8.encode('${settings.username}:${settings.webdavPassword}'))}',
      ...?headers,
    },
    responseType: ResponseType.plain,
  );

  Future<List<DavEntry>> _properties(
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
    final results = <DavEntry>[];
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
      final entryPath = canonicalDavPath(uri.path);
      if (!entryPath.startsWith(root)) {
        if (strict) throw const FormatException('WebDAV 未返回有效属性');
        continue;
      }
      results.add(
        DavEntry(
          isDirectory && !entryPath.endsWith('/') ? '$entryPath/' : entryPath,
          isDirectory,
          etag: property('getetag'),
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

  Future<List<DavEntry>> list(String path) async {
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
  Future<List<DavEntry>> listAll(String path) async {
    return _listChildren(path, strict: true);
  }

  Future<List<DavEntry>> _listChildren(
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

  Future<DavEntry?> stat(String path) async {
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

  Future<bool> exists(String path) async => await stat(path) != null;

  Future<void> move(String from, String to, {String? etag}) async {
    final response = await dio.requestUri<String>(
      url(from),
      options: options(
        headers: {
          'Destination': url(to).toString(),
          'Overwrite': 'F',
          if (etag != null && !etag.startsWith('W/')) 'If-Match': etag,
        },
      ).copyWith(method: 'MOVE'),
    );
    if (![201, 204].contains(response.statusCode)) {
      throw const FormatException('移动未确认成功，请刷新目录核对');
    }
  }

  Future<void> mkdir(String path) async {
    final response = await dio.requestUri<String>(
      url(path.endsWith('/') ? path : '$path/'),
      options: options().copyWith(method: 'MKCOL'),
    );
    if (response.statusCode != 201) throw const FormatException('创建目录未确认成功');
  }

  Future<void> remove(String path) async {
    final response = await dio.deleteUri<String>(url(path), options: options());
    if (![200, 204].contains(response.statusCode)) {
      throw const FormatException('删除未确认成功，请刷新目录核对');
    }
  }

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

  Future<void> download(String path, String destination) async {
    await dio.downloadUri(url(path), destination, options: options());
  }

  void close() => dio.close(force: true);
}
