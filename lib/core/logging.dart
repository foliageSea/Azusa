import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:stack_trace/stack_trace.dart';

import 'logging/file_log_store.dart';
import 'logging/log_archive_service.dart';
import 'logging/live_log_store.dart';

/// Provides a logger named after the concrete class.
mixin LoggingMixin {
  Logger get log => Logger(runtimeType.toString());
}

Future<void>? _loggingInitialization;
FileLogStore? _fileLogStore;

final fileLogStoreProvider = Provider<FileLogStore?>((ref) => _fileLogStore);

/// Configures console and daily file output once, keeping production warnings.
Future<void> initializeLogging({
  FileLogStore? fileStore,
  Future<Directory> Function()? temporaryDirectory,
}) => _loggingInitialization ??= _initializeLogging(
  fileStore,
  temporaryDirectory,
);

Future<void> _initializeLogging(
  FileLogStore? fileStore,
  Future<Directory> Function()? temporaryDirectory,
) async {
  final pending = <({String message, DateTime time})>[];
  var initializing = true;
  Logger.root.level = kDebugMode ? Level.FINE : Level.WARNING;
  Logger.root.onRecord.listen((record) {
    final output = StringBuffer(
      '${record.level.name}: ${record.time}: '
      '[${record.loggerName}] [${_logCallSite()}] ${record.message}',
    );
    if (record.error != null) output.write('\n${record.error}');
    if (record.stackTrace != null) output.write('\n${record.stackTrace}');
    final message = output.toString();
    applicationLogs.add(level: record.level, time: record.time, text: message);
    debugPrint(message);
    if (initializing) {
      pending.add((message: message, time: record.time));
    } else {
      _writeFileLog(message, record.time);
    }
  });
  try {
    final directory = fileStore == null
        ? await getApplicationSupportDirectory()
        : null;
    _fileLogStore =
        fileStore ??
        FileLogStore(directory: Directory('${directory!.path}/logs'));
    await _fileLogStore!.initialize();
  } catch (error) {
    // Never report file-logging failures via Logger: that would recurse.
    debugPrint(
      'File logging initialization failed; console remains available: $error',
    );
  } finally {
    initializing = false;
    for (final entry in pending) {
      _writeFileLog(entry.message, entry.time);
    }
    pending.clear();
  }
  final store = _fileLogStore;
  if (store != null) {
    try {
      await LogArchiveService(
        store: store,
        temporaryDirectory: temporaryDirectory,
      ).cleanupExpiredExports();
    } catch (error) {
      debugPrint('Temporary log export cleanup failed: $error');
    }
  }
}

void _writeFileLog(String message, DateTime time) {
  final store = _fileLogStore;
  if (store == null) return;
  unawaited(
    store.write(message, time: time).catchError((Object error) {
      debugPrint('File log write failed; console remains available: $error');
    }),
  );
}

String _logCallSite() {
  // onRecord is synchronous, so this trace still contains the logging caller.
  // Keep it separate from record.stackTrace, which may describe an exception.
  final frames = Trace.current().frames;
  if (frames.isEmpty) return 'unknown';
  final loggingUri = frames.first.uri;
  for (final frame in frames) {
    if (frame.isCore ||
        frame.package == 'logging' ||
        frame.package == 'stack_trace' ||
        frame.uri == loggingUri) {
      continue;
    }
    final file = frame.uri.pathSegments.lastOrNull;
    if (file == null || file.isEmpty) continue;
    return '$file:${frame.line ?? '?'}';
  }
  return 'unknown';
}
