import 'package:dio/dio.dart';

import 'dav/webdav.dart';
import 'dav/dav_paths.dart';
import 'connections/http_clients.dart';

enum TmdbMediaType { tv, movie }

class RenameItem {
  const RenameItem({
    required this.source,
    required this.targetName,
    this.reason = '',
    this.enabled = true,
    this.fingerprint,
    this.etag,
    this.targetDirectory,
    this.tmdbId,
    this.tmdbMediaType,
    this.mediaTitle,
    this.mediaYear,
    this.seasonNumber,
    this.episodeNumber,
    this.scope,
    this.destinationScope,
  });
  final String source, targetName, reason;
  final String? fingerprint, etag;
  final String? targetDirectory;
  final bool enabled;
  final int? tmdbId;
  final TmdbMediaType? tmdbMediaType;
  final String? mediaTitle;
  final int? mediaYear, seasonNumber, episodeNumber;

  /// The analyzed directory.
  final String? scope;

  /// Base for new folders: the analyzed directory or its immediate parent.
  final String? destinationScope;

  Uri? get tmdbUrl => tmdbId != null && tmdbId! > 0 && tmdbMediaType != null
      ? Uri.https('www.themoviedb.org', '/${tmdbMediaType!.name}/$tmdbId')
      : null;

  String get parent => source.substring(0, source.lastIndexOf('/') + 1);
  String get target =>
      '${targetDirectory ?? parent}${Uri.encodeComponent(targetName)}';

  RenameItem copyWith({String? targetName, bool? enabled}) =>
      _copy(targetName: targetName, enabled: enabled);

  RenameItem withTargetDirectory(
    String? directory, {
    String? destinationScope,
  }) => _copy(
    targetDirectory: () => directory,
    destinationScope: destinationScope,
  );

  RenameItem _copy({
    String? targetName,
    bool? enabled,
    String? Function()? targetDirectory,
    String? destinationScope,
  }) => RenameItem(
    source: source,
    targetName: targetName ?? this.targetName,
    reason: reason,
    enabled: enabled ?? this.enabled,
    fingerprint: fingerprint,
    etag: etag,
    targetDirectory: targetDirectory == null
        ? this.targetDirectory
        : targetDirectory(),
    tmdbId: tmdbId,
    tmdbMediaType: tmdbMediaType,
    mediaTitle: mediaTitle,
    mediaYear: mediaYear,
    seasonNumber: seasonNumber,
    episodeNumber: episodeNumber,
    scope: scope,
    destinationScope: destinationScope ?? this.destinationScope,
  );
}

String? validatePlan(List<RenameItem> plan, List<DavEntry> entries) {
  final targets = <String>{};
  final sources = plan.where((e) => e.enabled).map((e) => e.source).toSet();
  final existing = {for (final entry in entries) entry.path: entry};
  final seen = <String>{};
  for (final item in plan.where((e) => e.enabled)) {
    if (!seen.add(item.source)) return '同一源文件出现多次';
    final source = existing[item.source];
    if (source == null || source.directory) {
      return '源文件已变化：${displayDavPath(item.source)}';
    }
    if (item.fingerprint != null && item.fingerprint != source.fingerprint) {
      return '源文件属性已变化，请重新生成建议';
    }
    final nameError = fileNameError(item.targetName);
    if (nameError != null) return nameError;
    final directory = item.targetDirectory;
    final destinationScope = item.destinationScope ?? item.scope;
    if (item.destinationScope != null &&
        (item.scope == null ||
            (item.destinationScope != item.scope &&
                item.destinationScope != parentDavDirectory(item.scope!)))) {
      return '目标目录无效';
    }
    if (directory != null &&
        (!directory.startsWith('/') ||
            !directory.endsWith('/') ||
            !(item.scope == null
                ? item.parent.startsWith(directory)
                : directory.startsWith(destinationScope!)))) {
      return '目标目录无效';
    }
    try {
      if (canonicalDavPath(item.target) != item.target) return '目标目录无效';
    } on FormatException {
      return '目标目录无效';
    }
    final oldName = Uri.decodeComponent(item.source.split('/').last);
    final oldExtension = oldName.contains('.')
        ? oldName.substring(oldName.lastIndexOf('.'))
        : '';
    if (oldExtension.isNotEmpty &&
        !item.targetName.toLowerCase().endsWith(oldExtension.toLowerCase())) {
      return '必须保留扩展名：$oldExtension';
    }
    if (!targets.add(item.target.toLowerCase())) {
      return '目标文件名重复：${item.targetName}';
    }
    if (item.target != item.source &&
        existing.keys.any(
          (p) => p.toLowerCase() == item.target.toLowerCase(),
        )) {
      return '目标已存在：${item.targetName}';
    }
    if (sources.contains(item.target) && item.target != item.source) {
      return '目标与待处理文件冲突';
    }
  }
  return null;
}

class ExecutionResult {
  const ExecutionResult(this.completed, this.error);
  final List<RenameItem> completed;
  final String? error;
}

class RenameExecutor {
  RenameExecutor(this.dav);
  final WebDavClient dav;
  bool running = false;

  Future<List<DavEntry>> _listIfPresent(String directory) async {
    try {
      return await dav.list(directory);
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) return const [];
      rethrow;
    }
  }

  /// Creates the folders between the item's scope and its target directory.
  Future<void> _ensureDirectory(
    RenameItem item,
    Set<String> ready,
    Future<void> Function(String path)? onCreatingDirectory,
    Future<void> Function(String path)? onDirectoryCreated,
  ) async {
    final scope = item.destinationScope ?? item.scope;
    final directory = item.targetDirectory;
    if (scope == null || directory == null || ready.contains(directory)) {
      return;
    }
    var path = scope;
    for (final segment
        in directory
            .substring(scope.length)
            .split('/')
            .where((segment) => segment.isNotEmpty)) {
      path = '$path$segment/';
      if (ready.contains(path)) continue;
      final current = await dav.stat(path);
      if (current == null) {
        await onCreatingDirectory?.call(path);
        await dav.mkdir(path);
        await onDirectoryCreated?.call(path);
      } else if (!current.directory) {
        throw StateError('目标目录被同名文件占用');
      }
      ready.add(path);
    }
  }

  Future<ExecutionResult> execute(
    List<RenameItem> plan, {
    void Function(int done, int total)? onProgress,
    Future<void> Function(RenameItem item)? onCompleted,
    Future<void> Function(RenameItem item)? onStarting,
    Future<void> Function(String path)? onCreatingDirectory,
    Future<void> Function(String path)? onDirectoryCreated,
  }) async {
    if (running) throw StateError('整理任务正在执行');
    running = true;
    final completed = <RenameItem>[];
    try {
      final selected = List<RenameItem>.of(
        plan.where((p) => p.enabled && p.source != p.target),
      );
      if (selected.isEmpty) return const ExecutionResult([], null);
      try {
        for (final item in selected) {
          dav.normalize(item.source);
          dav.normalize(item.target);
        }
      } on FormatException {
        return const ExecutionResult([], '目标目录无效');
      }
      final directories = {
        for (final item in selected) item.parent,
        for (final item in selected)
          if (item.targetDirectory != null) item.targetDirectory!,
      };
      final initial = <DavEntry>[];
      for (final directory in directories) {
        initial.addAll(await _listIfPresent(directory));
      }
      final error = validatePlan(selected, initial);
      if (error != null) return ExecutionResult(completed, error);
      final ready = <String>{};
      for (final (index, item) in selected.indexed) {
        try {
          final current = await dav.stat(item.source);
          if (current == null) throw StateError('源文件已不存在');
          if (item.fingerprint != null &&
              item.fingerprint != current.fingerprint) {
            throw StateError('源文件属性已变化');
          }
          await _ensureDirectory(
            item,
            ready,
            onCreatingDirectory,
            onDirectoryCreated,
          );
          if (await dav.exists(item.target)) throw StateError('目标文件已存在');
          await onStarting?.call(item);
          await dav.move(item.source, item.target, etag: item.etag);
          completed.add(item);
          await onCompleted?.call(item);
          onProgress?.call(index + 1, selected.length);
        } catch (e) {
          return ExecutionResult(
            completed,
            '${item.targetName}: ${serviceError(e)}',
          );
        }
      }
      return ExecutionResult(completed, null);
    } finally {
      running = false;
    }
  }
}
