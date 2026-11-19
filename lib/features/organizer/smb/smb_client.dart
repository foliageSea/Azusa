import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:dart_smb2/dart_smb2.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../file_server/file_server.dart';
import '../file_server/file_server_paths.dart';
import 'smb_connection.dart';

/// Stable, credential-free messages for the organizer's error presenters.
abstract final class SmbClientMessages {
  static const unsafePath = 'SMB 路径无效或不安全';
  static const rootMutation = '不能修改 SMB 共享根目录';
  static const reparsePoint = '不支持访问 SMB 符号链接或重解析点';
  static const incompleteListing = '无法确认 SMB 目录列表完整';
  static const notFound = 'SMB 文件、目录或共享不存在';
  static const alreadyExists = 'SMB 目标已存在';
  static const accessDenied = '没有 SMB 访问权限';
  static const authentication = 'SMB 身份验证失败';
  static const timeout = 'SMB 请求超时';
  static const connection = '无法连接到 SMB 共享';
  static const notDirectory = 'SMB 路径不是目录';
  static const isDirectory = 'SMB 路径是目录';
  static const notEmpty = 'SMB 目录非空';
  static const busy = 'SMB 文件或服务器正忙';
  static const diskFull = 'SMB 共享空间不足';
  static const unsupported = 'SMB 不支持此操作';
  static const closed = 'SMB 连接已关闭';
  static const invalidLength = 'SMB 上传长度无效';
  static const transferLength = 'SMB 上传长度与实际数据不符';
  static const failed = 'SMB 操作失败';
}

class SmbClient extends FileServerClient {
  SmbClient.forConnection(SmbConnection connection)
    : _connect = (() => _PoolBackend.connect(connection)),
      _stagingName = _randomStagingName {
    connection.validate();
  }

  @visibleForTesting
  SmbClient.withBackend(this._connect, {String Function()? stagingName})
    : _stagingName = stagingName ?? _randomStagingName;

  final Future<SmbBackend> Function() _connect;
  final String Function() _stagingName;
  Future<SmbBackend>? _connecting;
  SmbBackend? _backend;
  bool _closed = false;

  static const _hiddenOrSystem = 0x02 | 0x04;
  static const _reparseAttribute = 0x400;
  static const _chunkSize = 1024 * 1024;
  static final _deviceName = RegExp(
    r'^(?:CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³]|CONIN\$|CONOUT\$)$',
    caseSensitive: false,
  );

  static bool _safeName(String name) =>
      validFileName(name) &&
      !_deviceName.hasMatch(name.split('.').first.trimRight());

  @override
  String get root => '/';

  @override
  String normalize(String path) {
    final segments = _segments(path);
    if (segments.isEmpty) return root;
    return '/${segments.map(Uri.encodeComponent).join('/')}${path.endsWith('/') ? '/' : ''}';
  }

  static List<String> _segments(String path) {
    if (path == '/') return const [];
    if (!path.startsWith('/') || path.contains('?') || path.contains('#')) {
      throw const FormatException(SmbClientMessages.unsafePath);
    }
    try {
      final parts = path.split('/')..removeAt(0);
      if (parts.last.isEmpty) parts.removeLast();
      return parts.map((part) {
        final name = Uri.decodeComponent(part);
        if (!_safeName(name)) {
          throw const FormatException(SmbClientMessages.unsafePath);
        }
        return name;
      }).toList();
    } on FormatException {
      throw const FormatException(SmbClientMessages.unsafePath);
    } on ArgumentError {
      throw const FormatException(SmbClientMessages.unsafePath);
    }
  }

  static void _rejectRoot(List<String> segments) {
    if (segments.isEmpty) {
      throw const _SmbFailure(SmbClientMessages.rootMutation);
    }
  }

  Future<SmbBackend> _session() {
    if (_closed) throw const _SmbFailure(SmbClientMessages.closed);
    final backend = _backend;
    if (backend != null) return Future.value(backend);
    return _connecting ??= _open();
  }

  Future<SmbBackend> _open() async {
    try {
      final backend = await Future.sync(_connect);
      if (_closed) {
        _disconnect(backend);
        throw const _SmbFailure(SmbClientMessages.closed);
      }
      return _backend = backend;
    } finally {
      _connecting = null;
    }
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    final backend = _backend;
    _backend = null;
    if (backend != null) _disconnect(backend);
  }

  static void _disconnect(SmbBackend backend) =>
      Future.sync(backend.disconnect).ignore();

  static Future<T> _report<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on _SmbFailure catch (e) {
      throw StateError(e.message);
    } on Smb2Exception catch (e) {
      throw StateError(switch (e.type) {
        Smb2ErrorType.notFound => SmbClientMessages.notFound,
        Smb2ErrorType.alreadyExists => SmbClientMessages.alreadyExists,
        Smb2ErrorType.accessDenied => SmbClientMessages.accessDenied,
        Smb2ErrorType.auth => SmbClientMessages.authentication,
        Smb2ErrorType.timeout => SmbClientMessages.timeout,
        Smb2ErrorType.connection => SmbClientMessages.connection,
        Smb2ErrorType.notADirectory => SmbClientMessages.notDirectory,
        Smb2ErrorType.isADirectory => SmbClientMessages.isDirectory,
        Smb2ErrorType.notEmpty => SmbClientMessages.notEmpty,
        Smb2ErrorType.inUse => SmbClientMessages.busy,
        Smb2ErrorType.diskFull => SmbClientMessages.diskFull,
        Smb2ErrorType.notSupported => SmbClientMessages.unsupported,
        Smb2ErrorType.state => SmbClientMessages.closed,
        _ => SmbClientMessages.failed,
      });
    } on TimeoutException {
      throw StateError(SmbClientMessages.timeout);
    } catch (_) {
      throw StateError(SmbClientMessages.failed);
    }
  }

  static bool _isReparse(Smb2Stat stat) =>
      stat.type == Smb2FileType.link ||
      stat.attributes & _reparseAttribute != 0;

  static void _rejectReparse(Smb2Stat stat) {
    if (_isReparse(stat)) {
      throw const _SmbFailure(SmbClientMessages.reparsePoint);
    }
  }

  static String _child(String parent, String name) =>
      parent.isEmpty ? name : '$parent/$name';

  static bool _confirmedMissing(Smb2Exception e) =>
      e.type == Smb2ErrorType.notFound &&
      switch (e.ntStatus) {
        0xC000000F || 0xC0000034 || 0xC000003A => true,
        _ => false,
      };

  /// A normal CREATE/stat can follow a link. Inspect each entry in its parent
  /// before using it, and send only the name actually reported by the server.
  /// This is a path-based check, not a guarantee against concurrent changes.
  static Future<_Resolved?> _lookup(
    SmbBackend backend,
    String parent,
    String name,
  ) async {
    final entries = await backend.listDirectory(parent);
    final folded = name.toLowerCase();
    Smb2DirEntry? match;
    var matches = 0;
    for (final entry in entries) {
      if (entry.name.toLowerCase() != folded) continue;
      if (++matches > 1) {
        throw const _SmbFailure(SmbClientMessages.incompleteListing);
      }
      // Do not assume that case aliases name the same file: some SMB shares
      // are case-sensitive. Consumers use the exact names from our listings.
      if (entry.name == name) match = entry;
    }
    if (match != null) {
      if (!_safeName(match.name)) {
        throw const _SmbFailure(SmbClientMessages.incompleteListing);
      }
      _rejectReparse(match.stat);
      return _Resolved(_child(parent, match.name), match.stat);
    }
    // Enumeration can omit entries (e.g. access-based enumeration), and the
    // server may resolve aliases. Don't use a path it resolves unless we have
    // the corresponding directory entry's reparse metadata.
    try {
      final stat = await backend.stat(_child(parent, name));
      _rejectReparse(stat);
    } on Smb2Exception catch (e) {
      if (_confirmedMissing(e)) return null;
      rethrow;
    }
    throw const _SmbFailure(SmbClientMessages.incompleteListing);
  }

  static Future<_Resolved?> _resolve(
    SmbBackend backend,
    List<String> segments,
  ) async {
    if (segments.isEmpty) {
      final stat = await backend.stat('');
      _rejectReparse(stat);
      return _Resolved('', stat);
    }
    var parent = '';
    for (var i = 0; i < segments.length; i++) {
      final entry = await _lookup(backend, parent, segments[i]);
      if (entry == null || i == segments.length - 1) return entry;
      if (!entry.stat.isDirectory) {
        throw const _SmbFailure(SmbClientMessages.notDirectory);
      }
      parent = entry.path;
    }
    throw const _SmbFailure(SmbClientMessages.failed);
  }

  static Future<_Resolved> _require(
    SmbBackend backend,
    List<String> segments,
  ) async =>
      await _resolve(backend, segments) ??
      (throw const _SmbFailure(SmbClientMessages.notFound));

  static Future<String> _parent(
    SmbBackend backend,
    List<String> segments,
  ) async {
    if (segments.length == 1) return '';
    final parent = await _require(
      backend,
      segments.sublist(0, segments.length - 1),
    );
    if (!parent.stat.isDirectory) {
      throw const _SmbFailure(SmbClientMessages.notDirectory);
    }
    return parent.path;
  }

  static Future<String> _unused(
    SmbBackend backend,
    String parent,
    String name,
  ) async {
    if (await _lookup(backend, parent, name) != null) {
      throw const _SmbFailure(SmbClientMessages.alreadyExists);
    }
    return _child(parent, name);
  }

  static FileServerEntry _entry(String nativePath, Smb2Stat stat) {
    final directory = nativePath.isEmpty || stat.isDirectory;
    final path = nativePath.isEmpty
        ? '/'
        : '/${nativePath.split('/').map(Uri.encodeComponent).join('/')}${directory ? '/' : ''}';
    return FileServerEntry(
      path,
      directory,
      size: directory ? null : stat.size,
      modified: stat.modified.toUtc().toIso8601String(),
    );
  }

  @override
  Future<FileServerEntry?> stat(String path) async {
    final segments = _segments(path);
    return _report(() async {
      final item = await _resolve(await _session(), segments);
      return item == null ? null : _entry(item.path, item.stat);
    });
  }

  @override
  Future<List<FileServerEntry>> list(String path) => _list(path, all: false);

  @override
  Future<List<FileServerEntry>> listAll(String path) => _list(path, all: true);

  Future<List<FileServerEntry>> _list(String path, {required bool all}) async {
    final segments = _segments(path);
    return _report(() async {
      final backend = await _session();
      var directory = '';
      if (segments.isNotEmpty) {
        final item = await _require(backend, segments);
        if (!item.stat.isDirectory) {
          throw const _SmbFailure(SmbClientMessages.notDirectory);
        }
        directory = item.path;
      }
      // The pinned native opendir buffers all QUERY_DIRECTORY pages through
      // STATUS_NO_MORE_FILES; any other terminal status fails the whole call.
      final entries = await backend.listDirectory(directory);
      final counts = <String, int>{};
      for (final entry in entries) {
        counts.update(
          entry.name.toLowerCase(),
          (n) => n + 1,
          ifAbsent: () => 1,
        );
      }
      final result = <FileServerEntry>[];
      for (final entry in entries) {
        if (entry.name == '.' || entry.name == '..') continue;
        if (!_safeName(entry.name) ||
            counts[entry.name.toLowerCase()] != 1 ||
            _isReparse(entry.stat)) {
          if (all) throw const _SmbFailure(SmbClientMessages.incompleteListing);
          continue;
        }
        if (!all && entry.stat.attributes & _hiddenOrSystem != 0) continue;
        result.add(_entry(_child(directory, entry.name), entry.stat));
      }
      return result;
    });
  }

  @override
  Future<void> move(String from, String to, {String? versionToken}) async {
    final source = _segments(from);
    final target = _segments(to);
    return _report(() async {
      _rejectRoot(source);
      _rejectRoot(target);
      final backend = await _session();
      final item = await _require(backend, source);
      final parent = await _parent(backend, target);
      final destination = await _unused(backend, parent, target.last);
      // The library has no conditional rename API. The server enforces no replace.
      await backend.rename(item.path, destination, overwrite: false);
    });
  }

  @override
  Future<void> mkdir(String path) async {
    final segments = _segments(path);
    return _report(() async {
      _rejectRoot(segments);
      final backend = await _session();
      final parent = await _parent(backend, segments);
      await backend.mkdir(await _unused(backend, parent, segments.last));
    });
  }

  @override
  Future<void> remove(String path) async {
    final segments = _segments(path);
    return _report(() async {
      _rejectRoot(segments);
      final backend = await _session();
      final item = await _require(backend, segments);
      if (item.stat.isDirectory) {
        await backend.rmdir(item.path);
      } else {
        await backend.deleteFile(item.path);
      }
    });
  }

  @override
  Future<void> download(String path, String destination) async {
    final segments = _segments(path);
    return _report(() async {
      if (segments.isEmpty) {
        throw const _SmbFailure(SmbClientMessages.isDirectory);
      }
      final backend = await _session();
      final item = await _require(backend, segments);
      if (item.stat.isDirectory) {
        throw const _SmbFailure(SmbClientMessages.isDirectory);
      }
      await backend.download(item.path, destination);
    });
  }

  @override
  Future<void> upload(String path, Stream<List<int>> bytes, int length) async {
    final segments = _segments(path);
    return _report(() async {
      _rejectRoot(segments);
      if (path.endsWith('/')) {
        throw const _SmbFailure(SmbClientMessages.isDirectory);
      }
      if (length < 0) throw const _SmbFailure(SmbClientMessages.invalidLength);
      final backend = await _session();
      final parent = await _parent(backend, segments);
      final destination = await _unused(backend, parent, segments.last);
      final stageName = _stagingName();
      if (!validFileName(stageName)) {
        throw const _SmbFailure(SmbClientMessages.unsafePath);
      }
      // A successful exclusive mkdir is the only event that grants ownership.
      // In particular, a failed or ambiguous mkdir never triggers cleanup.
      await backend.mkdir(_child(parent, stageName));
      final stageSegments = [...segments.take(segments.length - 1), stageName];
      _Resolved? stage;
      var startedWriting = false;
      var published = false;
      try {
        stage = await _require(backend, stageSegments);
        if (!stage.stat.isDirectory) {
          throw const _SmbFailure(SmbClientMessages.notDirectory);
        }
        final part = await _unused(backend, stage.path, 'payload');
        startedWriting = true;
        final reported = await backend.streamWrite(
          part,
          _checkedBytes(bytes, length),
          length,
        );
        if (reported != length) {
          throw const _SmbFailure(SmbClientMessages.transferLength);
        }
        final currentStage = await _checkStage(backend, stageSegments, stage);
        final stagedFile = await _lookup(backend, currentStage.path, 'payload');
        if (stagedFile == null ||
            !stagedFile.stat.isFile ||
            stagedFile.stat.size != length) {
          throw const _SmbFailure(SmbClientMessages.transferLength);
        }
        // Recheck the destination parent after streaming. No replacement is
        // allowed even if another client creates the destination after this.
        final currentParent = await _parent(backend, segments);
        if (currentParent != parent) {
          throw const _SmbFailure(SmbClientMessages.unsafePath);
        }
        await backend.rename(stagedFile.path, destination, overwrite: false);
        published = true;
      } finally {
        if (stage != null && stage.stat.fileId != 0) {
          await _cleanStage(
            backend,
            stageSegments,
            stage,
            startedWriting && !published,
          );
        }
      }
    });
  }

  static Future<_Resolved> _checkStage(
    SmbBackend backend,
    List<String> stageSegments,
    _Resolved owned,
  ) async {
    final current = await _require(backend, stageSegments);
    if (!current.stat.isDirectory ||
        current.path != owned.path ||
        current.stat.fileId != owned.stat.fileId ||
        current.stat.created != owned.stat.created) {
      throw const _SmbFailure(SmbClientMessages.unsafePath);
    }
    return current;
  }

  static Future<void> _cleanStage(
    SmbBackend backend,
    List<String> stageSegments,
    _Resolved owned,
    bool removePart,
  ) async {
    try {
      final stage = await _checkStage(backend, stageSegments, owned);
      if (removePart) {
        final part = await _lookup(backend, stage.path, 'payload');
        if (part != null && part.stat.isFile) {
          await backend.deleteFile(part.path);
        }
      }
      // Never recurse or delete anything outside the owned staging directory.
      await backend.rmdir(stage.path);
    } catch (_) {
      // Preserve the original outcome. A crash, lost connection or changed
      // directory may leave an orphaned stage.
    }
  }

  static Stream<Uint8List> _checkedBytes(
    Stream<List<int>> bytes,
    int length,
  ) async* {
    var total = 0;
    await for (final chunk in bytes.timeout(_PoolBackend.idleTimeout)) {
      if (chunk.length > length - total) {
        throw const _SmbFailure(SmbClientMessages.transferLength);
      }
      total += chunk.length;
      for (var start = 0; start < chunk.length; start += _chunkSize) {
        final end = min(start + _chunkSize, chunk.length);
        final view = chunk is Uint8List
            ? Uint8List.sublistView(chunk, start, end)
            : Uint8List.fromList(chunk.sublist(start, end));
        yield view;
      }
    }
    if (total != length) {
      throw const _SmbFailure(SmbClientMessages.transferLength);
    }
  }

  static String _randomStagingName() {
    final random = Random.secure();
    final suffix = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return '.azusa-stage-$suffix';
  }
}

class _SmbFailure implements Exception {
  const _SmbFailure(this.message);
  final String message;
}

class _Resolved {
  const _Resolved(this.path, this.stat);
  final String path;
  final Smb2Stat stat;
}

/// A test seam for the worker pool. All paths passed here are share-relative.
@visibleForTesting
abstract interface class SmbBackend {
  Future<List<Smb2DirEntry>> listDirectory(String path);
  Future<Smb2Stat> stat(String path);
  Future<void> mkdir(String path);
  Future<void> rmdir(String path);
  Future<void> deleteFile(String path);
  Future<void> rename(String from, String to, {required bool overwrite});
  Future<int> streamWrite(String path, Stream<Uint8List> chunks, int length);
  Future<void> download(String path, String destination);
  Future<void> disconnect();
}

class _PoolBackend implements SmbBackend {
  _PoolBackend(this._pool);
  final Smb2Pool _pool;
  static const requestTimeout = Duration(seconds: 10);
  static const idleTimeout = Duration(seconds: 40);

  static Future<SmbBackend> connect(SmbConnection connection) async =>
      _PoolBackend(
        await Smb2Pool.connect(
          host: connection.host.trim(),
          share: connection.share,
          user: connection.username.trim(),
          password: connection.password,
          domain: connection.domain.trim().isEmpty
              ? null
              : connection.domain.trim(),
          workers: 1,
          signing: true,
          // The pinned native library offers only SMB 2.0.2 through SMB 3.1.1.
          version: Smb2Version.any,
          timeout: requestTimeout,
        ),
      );

  // Bound paginated/queued requests as well as idle transfers. Cancel on
  // expiry so a request still waiting on the pool does not start afterwards.
  static Future<T> _timed<T>(
    Future<T> Function(Smb2CancelToken token, void Function() progress) body,
  ) async {
    final token = Smb2CancelToken();
    final expired = Completer<T>();
    Timer? timer;
    void progress() {
      timer?.cancel();
      if (expired.isCompleted) return;
      timer = Timer(idleTimeout, () {
        expired.completeError(TimeoutException(SmbClientMessages.timeout));
        token.cancel();
      });
    }

    progress();
    try {
      return await Future.any([
        expired.future,
        Future.sync(() => body(token, progress)),
      ]);
    } finally {
      timer?.cancel();
    }
  }

  @override
  Future<List<Smb2DirEntry>> listDirectory(String path) =>
      _timed((token, _) => _pool.listDirectory(path, cancelToken: token));

  @override
  Future<Smb2Stat> stat(String path) =>
      _timed((token, _) => _pool.stat(path, cancelToken: token));

  @override
  Future<void> mkdir(String path) =>
      _timed((token, _) => _pool.mkdir(path, cancelToken: token));

  @override
  Future<void> rmdir(String path) =>
      _timed((token, _) => _pool.rmdir(path, cancelToken: token));

  @override
  Future<void> deleteFile(String path) =>
      _timed((token, _) => _pool.deleteFile(path, cancelToken: token));

  @override
  Future<void> rename(String from, String to, {required bool overwrite}) =>
      _timed(
        (token, _) =>
            _pool.rename(from, to, overwrite: overwrite, cancelToken: token),
      );

  @override
  Future<int> streamWrite(String path, Stream<Uint8List> chunks, int length) =>
      _timed(
        (token, progress) => _pool.streamWrite(
          path,
          chunks,
          length: length,
          cancelToken: token,
          onProgress: (_, _) => progress(),
        ),
      );

  @override
  Future<void> download(String path, String destination) =>
      _timed((token, progress) async {
        await _pool.downloadToFile(
          path,
          destination,
          cancelToken: token,
          onProgress: (_, _) => progress(),
        );
      });

  @override
  Future<void> disconnect() => _pool.disconnect();
}
