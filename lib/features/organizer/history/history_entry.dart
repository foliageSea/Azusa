enum HistoryPathChange { rename, move, moveAndRename }

class HistoryEntry {
  const HistoryEntry({
    required this.raw,
    required this.message,
    required this.action,
    required this.completed,
    this.time,
    this.source,
    this.target,
    this.startedAt,
  });

  final String raw, message, action;
  final bool? completed;
  final DateTime? time, startedAt;
  final String? source, target;

  static String _normalizedPath(String path) =>
      path.replaceFirst(RegExp(r'/+$'), '');

  static String _fileName(String path) => _normalizedPath(path).split('/').last;

  static String _directory(String path) {
    final normalized = _normalizedPath(path);
    final separator = normalized.lastIndexOf('/');
    return separator < 0 ? '' : normalized.substring(0, separator);
  }

  HistoryPathChange? get pathChange {
    if (source == null || target == null) return null;
    final moved = _directory(source!) != _directory(target!);
    final renamed = _fileName(source!) != _fileName(target!);
    if (moved) {
      return renamed ? HistoryPathChange.moveAndRename : HistoryPathChange.move;
    }
    return renamed ? HistoryPathChange.rename : null;
  }

  bool get directoryChanged =>
      pathChange == HistoryPathChange.move ||
      pathChange == HistoryPathChange.moveAndRename;

  String? get sourceSummary => source == null
      ? null
      : directoryChanged
      ? source
      : _fileName(source!);

  String? get targetSummary => target == null
      ? null
      : directoryChanged
      ? target
      : _fileName(target!);

  static final _timestamp = RegExp(
    r'^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})?) ',
  );
  static final _operation = RegExp(
    r'^(准备|完成)(重命名| move| upload| delete| mkdir) ',
  );

  factory HistoryEntry.parse(String raw) {
    final stamp = _timestamp.firstMatch(raw);
    final message = stamp == null ? raw : raw.substring(stamp.end);
    final operation = _operation.firstMatch(message);
    final action = operation?.group(2)?.trim() ?? '';
    final payload = operation == null
        ? message
        : message.substring(operation.end);
    String? source, target;
    if (action == '重命名' || action == 'move') {
      final separator = payload.indexOf(' → ');
      if (separator >= 0) {
        source = payload.substring(0, separator);
        target = payload.substring(separator + 3);
      }
    } else if (const ['upload', 'delete', 'mkdir'].contains(action)) {
      source = payload.trimRight();
    }
    return HistoryEntry(
      raw: raw,
      message: message,
      action: action,
      completed: operation == null ? null : operation.group(1) == '完成',
      time: stamp == null ? null : DateTime.tryParse(stamp.group(1)!),
      source: source,
      target: target,
    );
  }

  String get title => switch (pathChange) {
    HistoryPathChange.rename => '重命名',
    HistoryPathChange.move => '移动',
    HistoryPathChange.moveAndRename => '移动并重命名',
    null => switch (action) {
      '重命名' => '重命名',
      'move' => '移动 / 重命名',
      'upload' => '上传文件',
      'delete' => '删除',
      'mkdir' => '新建文件夹',
      _ => '操作记录',
    },
  };

  String get _key => message.replaceFirst(RegExp(r'^(准备|完成)'), '');

  HistoryEntry _withStart(DateTime? start) => HistoryEntry(
    raw: raw,
    message: message,
    action: action,
    completed: completed,
    time: time,
    source: source,
    target: target,
    startedAt: start,
  );

  static List<HistoryEntry> fromRecords(List<String> records) {
    final entries = <HistoryEntry?>[];
    final pending = <String, List<int>>{};
    for (final raw in records) {
      var entry = HistoryEntry.parse(raw);
      if (entry.completed == false) {
        pending.putIfAbsent(entry._key, () => []).add(entries.length);
      } else if (entry.completed == true) {
        final matches = pending[entry._key];
        if (matches != null && matches.isNotEmpty) {
          final index = matches.removeLast();
          entry = entry._withStart(entries[index]!.time);
          entries[index] = null;
        }
      }
      entries.add(entry);
    }
    return entries.whereType<HistoryEntry>().toList().reversed.toList();
  }
}
