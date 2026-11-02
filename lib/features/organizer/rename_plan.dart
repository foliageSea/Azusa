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
  });
  final String source, targetName, reason;
  final String? fingerprint, etag;
  final String? targetDirectory;
  final bool enabled;
  final int? tmdbId;
  final TmdbMediaType? tmdbMediaType;

  Uri? get tmdbUrl => tmdbId != null && tmdbId! > 0 && tmdbMediaType != null
      ? Uri.https('www.themoviedb.org', '/${tmdbMediaType!.name}/$tmdbId')
      : null;

  String get parent => source.substring(0, source.lastIndexOf('/') + 1);
  String get target =>
      '${targetDirectory ?? parent}${Uri.encodeComponent(targetName)}';

  RenameItem copyWith({String? targetName, bool? enabled}) => RenameItem(
    source: source,
    targetName: targetName ?? this.targetName,
    reason: reason,
    enabled: enabled ?? this.enabled,
    fingerprint: fingerprint,
    etag: etag,
    targetDirectory: targetDirectory,
    tmdbId: tmdbId,
    tmdbMediaType: tmdbMediaType,
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
    if (item.targetDirectory != null &&
        (!item.targetDirectory!.startsWith('/') ||
            !item.targetDirectory!.endsWith('/') ||
            !item.parent.startsWith(item.targetDirectory!))) {
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

  Future<ExecutionResult> execute(
    List<RenameItem> plan, {
    void Function(int done, int total)? onProgress,
    Future<void> Function(RenameItem item)? onCompleted,
    Future<void> Function(RenameItem item)? onStarting,
  }) async {
    if (running) throw StateError('整理任务正在执行');
    running = true;
    final completed = <RenameItem>[];
    try {
      final selected = List<RenameItem>.of(
        plan.where((p) => p.enabled && p.source != p.target),
      );
      if (selected.isEmpty) return const ExecutionResult([], null);
      final directories = {
        for (final item in selected) item.parent,
        for (final item in selected)
          if (item.targetDirectory != null) item.targetDirectory!,
      };
      final initial = <DavEntry>[];
      for (final directory in directories) {
        initial.addAll(await dav.list(directory));
      }
      final error = validatePlan(selected, initial);
      if (error != null) return ExecutionResult(completed, error);
      for (final (index, item) in selected.indexed) {
        try {
          final current = await dav.stat(item.source);
          if (current == null) throw StateError('源文件已不存在');
          if (item.fingerprint != null &&
              item.fingerprint != current.fingerprint) {
            throw StateError('源文件属性已变化');
          }
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
