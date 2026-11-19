import '../../../core/settings/settings.dart';
import '../smb/smb_connection.dart';
import 'configuration_backup.dart';
import 'connection_settings.dart';
import 'webdav_connections.dart';

class ConfigurationImportPreview {
  ConfigurationImportPreview({
    required this.backup,
    required List<WebDavConnection> existing,
    required ConnectionSettings globals,
    List<SmbConnection> existingSmb = const [],
  }) : additions = List.unmodifiable(_additions(backup, existing)),
       smbAdditions = List.unmodifiable(_smbAdditions(backup, existingSmb)),
       aiNeedsKey = _needsKey(backup.ai, globals),
       previousAiUrl = globals.aiUrl;

  final ConfigurationBackup backup;
  final List<BackupDav> additions;
  final List<BackupSmb> smbAdditions;
  final bool aiNeedsKey;
  final String previousAiUrl;
  int get skipped => (backup.webdav?.length ?? 0) - additions.length;
  int get smbSkipped => (backup.smb?.length ?? 0) - smbAdditions.length;

  static Iterable<BackupDav> _additions(
    ConfigurationBackup backup,
    List<WebDavConnection> existing,
  ) sync* {
    if (backup.webdav == null) return;
    final seen = {
      for (final dav in existing) backupDavIdentity(dav.url, dav.username),
    };
    for (final dav in backup.webdav!) {
      if (seen.add(backupDavIdentity(dav.url, dav.username))) yield dav;
    }
  }

  static Iterable<BackupSmb> _smbAdditions(
    ConfigurationBackup backup,
    List<SmbConnection> existing,
  ) sync* {
    final items = backup.smb;
    if (items == null) return;
    final seen = {for (final item in existing) item.scope};
    for (final item in items) {
      if (seen.add(item.toConnection(id: 'backup').scope)) yield item;
    }
  }

  static bool _needsKey(BackupAi? ai, ConnectionSettings globals) =>
      ai != null &&
      ai.key == null &&
      globals.aiKey.isNotEmpty &&
      ai.url != globals.aiUrl;

  ConnectionSettings mergeGlobals(
    ConnectionSettings globals,
    Set<BackupSection> selected, {
    String? replacementAiKey,
  }) {
    final ai = selected.contains(BackupSection.ai) ? backup.ai : null;
    final tmdb = selected.contains(BackupSection.tmdb) ? backup.tmdb : null;
    if (_needsKey(ai, globals) && (replacementAiKey?.trim().isEmpty ?? true)) {
      throw const ConfigurationImportChanged();
    }
    return globals.copyWith(
      aiUrl: ai?.url,
      model: ai?.model,
      proxyAi: ai?.proxy,
      aiKey: ai?.key ?? (ai == null ? null : replacementAiKey?.trim()),
      proxyTmdb: tmdb?.proxy,
      tmdbToken: tmdb?.token,
    );
  }

  AppSettings mergeNaming(AppSettings settings) => settings.copyWith(
    namingLanguage: backup.tmdb?.language,
    namingFormat: backup.tmdb?.format,
  );
}

class ConfigurationImportChanged implements Exception {
  const ConfigurationImportChanged();
}

class ConfigurationImportRollbackFailed implements Exception {
  const ConfigurationImportRollbackFailed();
}
