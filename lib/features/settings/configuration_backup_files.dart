import 'dart:ui';
import 'dart:typed_data' show BytesBuilder;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../organizer/connections/configuration_backup.dart';

final configurationBackupFilesProvider = Provider<ConfigurationBackupFiles>(
  (ref) => const ConfigurationBackupFiles(),
);

class ConfigurationBackupFiles {
  const ConfigurationBackupFiles();

  static const _types = [
    XTypeGroup(
      label: 'JSON',
      extensions: ['json'],
      mimeTypes: ['application/json'],
      uniformTypeIdentifiers: ['public.json'],
    ),
  ];

  Future<Uint8List?> open() async {
    final file = await openFile(acceptedTypeGroups: _types);
    if (file == null) return null;
    const max = ConfigurationBackupCodec.maxBytes;
    if (await file.length() > max) {
      throw const BackupException(BackupProblem.tooLarge);
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in file.openRead()) {
      if (builder.length + chunk.length > max) {
        throw const BackupException(BackupProblem.tooLarge);
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  Future<bool> save(Uint8List bytes, {Rect? sharePositionOrigin}) async {
    const name = 'azusa-configuration.json';
    final file = XFile.fromData(
      bytes,
      name: name,
      mimeType: 'application/json',
    );
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [file],
          fileNameOverrides: [name],
          sharePositionOrigin: sharePositionOrigin,
        ),
      );
      return result.status != ShareResultStatus.dismissed;
    }
    final destination = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: _types,
    );
    if (destination == null) return false;
    await file.saveTo(destination.path);
    return true;
  }
}
