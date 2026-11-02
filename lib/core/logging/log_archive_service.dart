import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';

import 'file_log_store.dart';
import 'runtime_environment_report.dart';

class LogArchiveService {
  static const fileNamePrefix = 'forui-logs-';
  static const environmentFileName = 'runtime-environment.txt';

  LogArchiveService({
    required this.store,
    Future<Directory> Function()? temporaryDirectory,
    DateTime Function()? clock,
  }) : _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
       _clock = clock ?? DateTime.now;

  final FileLogStore store;
  final Future<Directory> Function() _temporaryDirectory;
  final DateTime Function() _clock;

  Future<Directory> _exportRoot() async {
    final temporary = await _temporaryDirectory();
    return Directory('${temporary.path}/forui-log-exports')
        .create(recursive: true);
  }

  /// Retain shared archives for a day, rather than deleting while another app
  /// might still be reading them. Only our own export-* directories are removed.
  Future<void> cleanupExpiredExports() async {
    final root = await _exportRoot();
    final cutoff = _clock().subtract(const Duration(days: 1));
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory ||
          !RegExp(
            r'^export-[\w-]+$',
          ).hasMatch(entity.uri.pathSegments.where((s) => s.isNotEmpty).last)) {
        continue;
      }
      if ((await entity.stat()).modified.isBefore(cutoff)) {
        await entity.delete(recursive: true);
      }
    }
  }

  /// The returned ZIP and snapshots live in their own disposable directory.
  Future<File?> createArchive({
    RuntimeEnvironmentReport? environmentReport,
  }) async {
    await cleanupExpiredExports();
    final root = await _exportRoot();
    final session = await root.createTemp('export-');
    try {
      final files = await store.snapshot(Directory('${session.path}/snapshot'));
      if (files.isEmpty) {
        await session.delete(recursive: true);
        return null;
      }
      final exportedAt = _clock();
      final report =
          environmentReport ?? await RuntimeEnvironmentReport.collect();
      final environmentFile = await File(
        '${session.path}/snapshot/$environmentFileName',
      ).writeAsString(report.toText(exportedAt: exportedAt));
      final stamp = exportedAt.toLocal().toIso8601String().replaceAll(
        RegExp(r'[:.]'),
        '-',
      );
      final archive = File('${session.path}/$fileNamePrefix$stamp.zip');
      final paths = [
        ...files,
        environmentFile,
      ].map((file) => file.path).toList();
      final zipPath = archive.path;
      // Stream from the snapshots in a worker isolate, without blocking the UI
      // or holding every retained day's contents in memory.
      await Isolate.run(() => _createZip(paths, zipPath));
      await Directory('${session.path}/snapshot').delete(recursive: true);
      return archive;
    } catch (_) {
      if (await session.exists()) await session.delete(recursive: true);
      rethrow;
    }
  }
}

void _createZip(List<String> paths, String destination) {
  final encoder = ZipFileEncoder()..create(destination);
  try {
    for (final path in paths) {
      final file = File(path);
      encoder.addFileSync(file, file.uri.pathSegments.last);
    }
  } finally {
    encoder.closeSync();
  }
}
