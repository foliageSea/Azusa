import 'webdav.dart';

/// Traverses only strict descendants; repeated or out-of-scope paths are ignored.
Future<List<DavEntry>> scanMediaDirectories(
  WebDavClient dav,
  String root, {
  required bool recursive,
  void Function(String path, int count)? onProgress,
  void Function()? checkCancelled,
}) async {
  final result = <String, DavEntry>{};
  final pending = [root];
  final visited = <String>{};
  while (pending.isNotEmpty) {
    checkCancelled?.call();
    final path = pending.removeLast();
    if (!visited.add(path)) continue;
    onProgress?.call(path, result.length);
    final entries = await dav.list(path);
    checkCancelled?.call();
    for (final entry in entries) {
      if (!entry.path.startsWith(path) || entry.path == path) continue;
      result[entry.path] = entry;
      if (entry.directory && recursive) {
        pending.add(entry.path);
      }
    }
  }
  return result.values.toList();
}

class EmptyDirectoryCleaner {
  EmptyDirectoryCleaner(this.dav);
  final WebDavClient dav;

  /// Includes parents whose only contents are other empty folders, bottom-up.
  Future<List<String>> scan(
    String root, {
    void Function(String)? onProgress,
    void Function()? checkCancelled,
  }) async {
    final empty = <String>{};
    final visited = <String>{};
    final pending = [(root, false)];
    final children = <String, List<DavEntry>>{};
    while (pending.isNotEmpty) {
      checkCancelled?.call();
      final (path, expanded) = pending.removeLast();
      if (expanded) {
        if (path != root &&
            children[path]!.every(
              (entry) => entry.directory && empty.contains(entry.path),
            )) {
          empty.add(path);
        }
        continue;
      }
      if (!visited.add(path)) continue;
      onProgress?.call(path);
      final entries = await dav.listAll(path);
      checkCancelled?.call();
      // Unexpected server responses must never qualify as empty.
      if (entries.any((e) => !e.path.startsWith(path) || e.path == path)) {
        throw StateError('目录响应无效：$path');
      }
      children[path] = entries;
      pending.add((path, true));
      for (final entry in entries.where((e) => e.directory)) {
        // Do not descend into hidden/system folders, but count them as contents.
        if (!entry.name.startsWith('.') &&
            entry.name != '#recycle' &&
            entry.name != '__MACOSX') {
          pending.add((entry.path, false));
        }
      }
    }
    return empty.toList();
  }

  Future<({int deleted, int skipped})> clean(
    String root,
    Iterable<String> selected, {
    void Function()? checkCancelled,
    Future<void> Function(String)? onDeleting,
    Future<void> Function(String)? onDeleted,
    void Function(int deleted, int skipped)? onProgress,
  }) async {
    final paths = selected.toSet().toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    var deleted = 0;
    var skipped = 0;
    for (final path in paths) {
      checkCancelled?.call();
      if (!root.endsWith('/') ||
          dav.normalize(path) != path ||
          path == root ||
          !path.startsWith(root) ||
          !path.endsWith('/') ||
          path.split('/').any((s) => s == '..' || s == '.')) {
        throw StateError('目录超出清理范围');
      }
      if ((await dav.listAll(path)).isNotEmpty) {
        skipped++;
      } else {
        checkCancelled?.call();
        await onDeleting?.call(path);
        checkCancelled?.call();
        await dav.remove(path);
        deleted++;
        onProgress?.call(deleted, skipped);
        await onDeleted?.call(path);
      }
      onProgress?.call(deleted, skipped);
    }
    return (deleted: deleted, skipped: skipped);
  }
}
