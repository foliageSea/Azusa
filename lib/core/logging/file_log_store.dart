import 'dart:io';

/// Serializes append, retention and snapshot operations in an app-private folder.
class FileLogStore {
  FileLogStore({
    required this.directory,
    this.retentionDays = 7,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    if (retentionDays < 1) {
      throw ArgumentError.value(
        retentionDays,
        'retentionDays',
        'Must be positive',
      );
    }
  }

  final Directory directory;
  final int retentionDays;
  final DateTime Function() _clock;
  Future<void> _pending = Future.value();
  DateTime? _lastCleanupDay;
  static final _fileName = RegExp(r'^app-(\d{4})-(\d{2})-(\d{2})\.log$');

  Future<void> initialize() => _enqueue(() => _prepare(_clock()));

  Future<void> write(String message, {required DateTime time}) =>
      _enqueue(() async {
        await _prepare(_clock());
        final date = _day(time);
        final file = File('${directory.path}/app-${_dateName(date)}.log');
        if (await FileSystemEntity.type(file.path, followLinks: false) ==
            FileSystemEntityType.link) {
          throw FileSystemException(
            'Refusing to write through a symbolic link',
            file.path,
          );
        }
        await file.writeAsString(
          '$message\n',
          mode: FileMode.append,
          flush: true,
        );
      });

  /// All earlier appends have been flushed when this completes.
  Future<void> flush() => _enqueue(() async {});

  /// Copies a consistent snapshot; subsequent writes cannot change these copies.
  Future<List<File>> snapshot(Directory destination) => _enqueue(() async {
    final now = _clock();
    await _prepare(now);
    final today = _day(now);
    final cutoff = today.subtract(Duration(days: retentionDays - 1));
    final files = <File>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final date = _fileDate(entity);
      if (date == null || date.isBefore(cutoff) || date.isAfter(today)) {
        continue;
      }
      if (await entity.length() > 0) files.add(entity);
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    await destination.create(recursive: true);
    return [
      for (final file in files)
        await file.copy('${destination.path}/${file.uri.pathSegments.last}'),
    ];
  });

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final next = _pending.then((_) => operation());
    // A failed operation must not poison later writes or exports.
    _pending = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<void> _prepare(DateTime now) async {
    await directory.create(recursive: true);
    final today = _day(now);
    if (today == _lastCleanupDay) return;
    final cutoff = today.subtract(Duration(days: retentionDays - 1));
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final date = _fileDate(entity);
      if (date != null && date.isBefore(cutoff)) await entity.delete();
    }
    _lastCleanupDay = today;
  }

  static DateTime _day(DateTime time) {
    final local = time.toLocal();
    // UTC is only used for calendar arithmetic, avoiding daylight-saving shifts.
    return DateTime.utc(local.year, local.month, local.day);
  }

  static String _dateName(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static DateTime? _fileDate(File file) {
    final match = _fileName.firstMatch(file.uri.pathSegments.last);
    if (match == null) return null;
    final year = int.parse(match[1]!);
    final month = int.parse(match[2]!);
    final day = int.parse(match[3]!);
    final date = DateTime.utc(year, month, day);
    return date.year == year && date.month == month && date.day == day
        ? date
        : null;
  }
}
