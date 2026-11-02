import 'dart:io';
import 'dart:ui';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../app_exception.dart';
import '../logging.dart';
import 'log_archive_service.dart';
import 'runtime_environment_report.dart';

enum LogExportResult { saved, shared, presented, cancelled, empty }

abstract interface class LogExportService {
  Future<LogExportResult> export({
    Rect? sharePositionOrigin,
    RuntimeEnvironmentReport? environmentReport,
  });
}

final logExportServiceProvider = Provider<LogExportService>((ref) {
  final store = ref.watch(fileLogStoreProvider);
  return NativeLogExportService(
    archives: store == null ? null : LogArchiveService(store: store),
  );
});

class NativeLogExportService implements LogExportService {
  NativeLogExportService({
    required this.archives,
    TargetPlatform? platform,
    Future<String?> Function(String name)? chooseSaveLocation,
    Future<ShareResult> Function(ShareParams params)? share,
  }) : _platform = platform ?? defaultTargetPlatform,
       _chooseSaveLocation = chooseSaveLocation ?? _saveLocation,
       _share = share ?? SharePlus.instance.share;

  final LogArchiveService? archives;
  final TargetPlatform _platform;
  final Future<String?> Function(String name) _chooseSaveLocation;
  final Future<ShareResult> Function(ShareParams params) _share;

  @override
  Future<LogExportResult> export({
    Rect? sharePositionOrigin,
    RuntimeEnvironmentReport? environmentReport,
  }) async {
    final service = archives;
    if (service == null) throw const AppException(FailureKind.storage);
    final archive = await service.createArchive(
      environmentReport: environmentReport,
    );
    if (archive == null) return LogExportResult.empty;
    var retainForSharing = false;
    try {
      if (_platform == TargetPlatform.android ||
          _platform == TargetPlatform.iOS) {
        // Some platforms cannot report completion; preserve the source file
        // until a later cleanup even if the share Future has already returned.
        retainForSharing = true;
        final result = await _share(
          ShareParams(
            files: [XFile(archive.path, mimeType: 'application/zip')],
            sharePositionOrigin: sharePositionOrigin,
          ),
        );
        return switch (result.status) {
          ShareResultStatus.success => LogExportResult.shared,
          ShareResultStatus.dismissed => LogExportResult.cancelled,
          ShareResultStatus.unavailable => LogExportResult.presented,
        };
      }
      final destination = await _chooseSaveLocation(
        archive.uri.pathSegments.last,
      );
      if (destination == null) return LogExportResult.cancelled;
      await archive.copy(destination);
      return LogExportResult.saved;
    } finally {
      if (!retainForSharing) {
        try {
          await archive.parent.delete(recursive: true);
        } on FileSystemException {
          // A completed save must not be reported as failed just because its
          // temporary source could not be removed; startup cleanup will retry.
        }
      }
    }
  }

  static Future<String?> _saveLocation(String name) async =>
      (await getSaveLocation(
        suggestedName: name,
        acceptedTypeGroups: [
          const XTypeGroup(label: 'ZIP', extensions: ['zip']),
        ],
      ))?.path;
}
