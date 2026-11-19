import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/settings/settings.dart';
import '../file_server/file_server_connection.dart';
import '../smb/smb_connection.dart';
import '../organizer_state.dart';
import 'configuration_backup.dart';
import 'configuration_transfer.dart';
import 'credential_vault.dart';
import 'file_server_connections.dart';
import 'webdav_connections.dart';

enum ProxyMode {
  direct('直连'),
  system('系统代理'),
  manual('手动代理');

  const ProxyMode(this.label);
  final String label;
}

class ConnectionSettings {
  const ConnectionSettings({
    FileServerConnection? fileServerConnection,
    String? connectionId,
    String webdavUrl = '',
    String username = '',
    this.aiUrl = 'https://api.openai.com/v1',
    this.model = '',
    this.proxyUrl = '',
    ProxyMode? proxyMode,
    this.proxyAi = true,
    this.proxyTmdb = true,
    bool proxyWebdav = false,
    String webdavPassword = '',
    this.aiKey = '',
    this.tmdbToken = '',
  }) : // Keep public named parameters separate from legacy-aware getters.
       // ignore: prefer_initializing_formals
       _fileServerConnection = fileServerConnection,
       _legacyConnectionId = connectionId,
       _legacyUrl = webdavUrl,
       _legacyUsername = username,
       _legacyPassword = webdavPassword,
       _legacyUseProxy = proxyWebdav,
       // ignore: prefer_initializing_formals
       _proxyMode = proxyMode;

  final FileServerConnection? _fileServerConnection;
  final String? _legacyConnectionId;
  final String _legacyUrl, _legacyUsername, _legacyPassword;
  final bool _legacyUseProxy;
  final ProxyMode? _proxyMode;

  FileServerConnection? get fileServerConnection {
    final active = _fileServerConnection;
    if (active != null) return active;
    if (_legacyUrl.trim().isEmpty) return null;
    return WebDavConnection(
      id: _legacyConnectionId ?? '',
      name: Uri.tryParse(_legacyUrl)?.host ?? 'WebDAV',
      url: _legacyUrl,
      username: _legacyUsername,
      password: _legacyPassword,
      useProxy: _legacyUseProxy,
    );
  }

  String? get connectionId => _fileServerConnection?.id ?? _legacyConnectionId;

  // Compatibility for legacy preference migration and WebDAV-only callers.
  WebDavConnection? get _activeWebDav => switch (_fileServerConnection) {
    final WebDavConnection webdav => webdav,
    _ => null,
  };
  String get webdavUrl =>
      _activeWebDav?.url ?? (_fileServerConnection == null ? _legacyUrl : '');
  String get username =>
      _activeWebDav?.username ??
      (_fileServerConnection == null ? _legacyUsername : '');
  String get webdavPassword =>
      _activeWebDav?.password ??
      (_fileServerConnection == null ? _legacyPassword : '');
  bool get proxyWebdav =>
      _activeWebDav?.useProxy ??
      (_fileServerConnection == null && _legacyUseProxy);

  // Preserve the behavior of callers and saved configurations predating modes.
  ProxyMode get proxyMode =>
      _proxyMode ??
      (proxyUrl.trim().isEmpty ? ProxyMode.direct : ProxyMode.manual);
  final String aiUrl, model, proxyUrl, aiKey, tmdbToken;
  final bool proxyAi, proxyTmdb;

  ConnectionSettings copyWith({
    FileServerConnection? fileServerConnection,
    bool clearFileServerConnection = false,
    String? connectionId,
    String? webdavUrl,
    String? username,
    String? aiUrl,
    String? model,
    String? proxyUrl,
    ProxyMode? proxyMode,
    String? webdavPassword,
    String? aiKey,
    String? tmdbToken,
    bool? proxyAi,
    bool? proxyTmdb,
    bool? proxyWebdav,
  }) {
    var active = clearFileServerConnection
        ? null
        : fileServerConnection ?? _fileServerConnection;
    if (fileServerConnection == null &&
        active is WebDavConnection &&
        (connectionId != null ||
            webdavUrl != null ||
            username != null ||
            webdavPassword != null ||
            proxyWebdav != null)) {
      active = WebDavConnection(
        id: connectionId ?? active.id,
        name: active.name,
        url: webdavUrl ?? active.url,
        username: username ?? active.username,
        password: webdavPassword ?? active.password,
        useProxy: proxyWebdav ?? active.useProxy,
      );
    }
    final keepLegacy = !clearFileServerConnection && active == null;
    return ConnectionSettings(
      fileServerConnection: active,
      connectionId: keepLegacy ? connectionId ?? _legacyConnectionId : null,
      webdavUrl: keepLegacy ? webdavUrl ?? _legacyUrl : '',
      username: keepLegacy ? username ?? _legacyUsername : '',
      aiUrl: aiUrl ?? this.aiUrl,
      model: model ?? this.model,
      proxyUrl: proxyUrl ?? this.proxyUrl,
      proxyMode: proxyMode ?? _proxyMode,
      webdavPassword: keepLegacy ? webdavPassword ?? _legacyPassword : '',
      aiKey: aiKey ?? this.aiKey,
      tmdbToken: tmdbToken ?? this.tmdbToken,
      proxyAi: proxyAi ?? this.proxyAi,
      proxyTmdb: proxyTmdb ?? this.proxyTmdb,
      proxyWebdav: keepLegacy && (proxyWebdav ?? _legacyUseProxy),
    );
  }
}

class ConnectionRepository {
  ConnectionRepository(this.preferences, this.secrets);
  final SharedPreferencesAsync preferences;
  final FlutterSecureStorage secrets;
  CredentialVault get credentials => CredentialVault.forStorage(secrets);
  static const _key = 'azusa.connections.v1';

  Future<ConnectionSettings> load({bool includeWebdav = true}) async {
    final raw = await preferences.getString(_key);
    final data = raw == null
        ? <String, dynamic>{}
        : jsonDecode(raw) as Map<String, dynamic>;
    return ConnectionSettings(
      webdavUrl: includeWebdav ? data['webdavUrl'] as String? ?? '' : '',
      username: includeWebdav ? data['username'] as String? ?? '' : '',
      aiUrl: data['aiUrl'] as String? ?? 'https://api.openai.com/v1',
      model: data['model'] as String? ?? '',
      proxyUrl: data['proxyUrl'] as String? ?? '',
      proxyMode: ProxyMode.values
          .where((mode) => mode.name == data['proxyMode'])
          .firstOrNull,
      proxyAi: data['proxyAi'] as bool? ?? true,
      proxyTmdb: data['proxyTmdb'] as bool? ?? true,
      proxyWebdav: data['proxyWebdav'] as bool? ?? false,
      webdavPassword: includeWebdav
          ? await credentials.read('azusa.webdavPassword') ?? ''
          : '',
      aiKey: await credentials.read('azusa.aiKey') ?? '',
      tmdbToken: await credentials.read('azusa.tmdbToken') ?? '',
    );
  }

  Future<void> save(
    ConnectionSettings value, {
    bool includeWebdav = true,
  }) async {
    await credentials.update({
      if (includeWebdav) 'azusa.webdavPassword': value.webdavPassword,
      'azusa.aiKey': value.aiKey,
      'azusa.tmdbToken': value.tmdbToken,
    });
    await preferences.setString(
      _key,
      jsonEncode({
        if (includeWebdav) 'webdavUrl': value.webdavUrl,
        if (includeWebdav) 'username': value.username,
        'aiUrl': value.aiUrl,
        'model': value.model,
        'proxyUrl': value.proxyUrl,
        'proxyMode': value.proxyMode.name,
        'proxyAi': value.proxyAi,
        'proxyTmdb': value.proxyTmdb,
        if (includeWebdav) 'proxyWebdav': value.proxyWebdav,
      }),
    );
  }
}

final connectionRepositoryProvider = Provider((ref) {
  final storage = Platform.isMacOS
      ? const FlutterSecureStorage(mOptions: CredentialVault.macOsOptions)
      : const FlutterSecureStorage();
  return ConnectionRepository(ref.watch(preferencesProvider), storage);
});
final connectionSettingsProvider =
    AsyncNotifierProvider<ConnectionSettingsController, ConnectionSettings>(
      ConnectionSettingsController.new,
    );

class ConnectionSettingsController extends AsyncNotifier<ConnectionSettings> {
  bool _mutating = false;
  void retryLoad() {
    ref.read(connectionRepositoryProvider).credentials.retryFailedLoad();
    ref.invalidateSelf();
  }

  @override
  Future<ConnectionSettings> build() async {
    final repository = ref.read(webDavConnectionsRepositoryProvider);
    final globals = await ref
        .read(connectionRepositoryProvider)
        .load(includeWebdav: !await repository.migrated());
    await repository.initialize(globals);
    return _resolve(globals);
  }

  Future<ConnectionSettings> _resolve(ConnectionSettings globals) async {
    final active = await ref
        .read(fileServerConnectionsRepositoryProvider)
        .active();
    return globals.copyWith(
      fileServerConnection: active,
      clearFileServerConnection: active == null,
    );
  }

  Future<void> _change(
    Future<void> Function() action, {
    bool reset = false,
    ConnectionSettings? globals,
  }) async {
    final organizer = ref.read(organizerProvider);
    if (_mutating || organizer.busy || organizer.executing) {
      throw StateError('请等待当前操作完成');
    }
    _mutating = true;
    final controller = ref.read(organizerProvider.notifier);
    controller.beginConnectionChange();
    var succeeded = false;
    try {
      await action();
      succeeded = true;
      final current = globals ?? state.requireValue;
      try {
        state = AsyncData(await _resolve(current));
      } catch (e, stack) {
        state = AsyncError(e, stack);
        rethrow;
      }
    } finally {
      controller.endConnectionChange(reset: reset && succeeded);
      _mutating = false;
    }
  }

  Future<void> saveConnection(FileServerConnection connection) => _change(
    () => ref.read(fileServerConnectionsRepositoryProvider).save(connection),
    reset: connection.id == state.requireValue.connectionId,
  );

  Future<void> selectConnection(String id) async {
    if (id == state.requireValue.connectionId) return;
    await _change(
      () => ref.read(fileServerConnectionsRepositoryProvider).select(id),
      reset: true,
    );
    await ref.read(organizerProvider.notifier).open(null);
  }

  Future<void> deleteConnection(String id) => _change(
    () => ref.read(fileServerConnectionsRepositoryProvider).remove(id),
    reset: id == state.requireValue.connectionId,
  );

  Future<void> save(ConnectionSettings value) async {
    await _change(
      () => ref
          .read(connectionRepositoryProvider)
          .save(value, includeWebdav: false),
      globals: value,
    );
  }

  Future<ConfigurationBackup> exportConfiguration(
    Set<BackupSection> selected, {
    required bool includeCredentials,
  }) async {
    final globals = state.requireValue;
    final settings = ref.read(settingsProvider);
    final webdav = selected.contains(BackupSection.webdav)
        ? await ref
              .read(webDavConnectionsRepositoryProvider)
              .load(includePasswords: includeCredentials)
        : null;
    final smb = selected.contains(BackupSection.smb)
        ? (await ref
                  .read(fileServerConnectionsRepositoryProvider)
                  .load(includePasswords: includeCredentials))
              .whereType<SmbConnection>()
        : null;
    String? credential(String value) =>
        includeCredentials && value.isNotEmpty ? value : null;
    return ConfigurationBackup(
      webdav: webdav
          ?.map(
            (dav) => (
              name: dav.name,
              url: dav.url,
              username: dav.username,
              proxy: dav.useProxy,
              password: credential(dav.password),
            ),
          )
          .toList(),
      smb: smb
          ?.map(
            (connection) => (
              name: connection.name,
              host: connection.host,
              share: connection.share,
              domain: connection.domain,
              username: connection.username,
              password: credential(connection.password),
            ),
          )
          .toList(),
      ai: selected.contains(BackupSection.ai)
          ? (
              url: globals.aiUrl,
              model: globals.model,
              proxy: globals.proxyAi,
              key: credential(globals.aiKey),
            )
          : null,
      tmdb: selected.contains(BackupSection.tmdb)
          ? (
              language: settings.namingLanguage,
              format: settings.namingFormat,
              proxy: globals.proxyTmdb,
              token: credential(globals.tmdbToken),
            )
          : null,
    );
  }

  Future<ConfigurationImportPreview> previewConfiguration(
    ConfigurationBackup backup,
  ) async => ConfigurationImportPreview(
    backup: backup,
    existing: backup.webdav == null
        ? const []
        : await ref
              .read(webDavConnectionsRepositoryProvider)
              .load(includePasswords: false),
    existingSmb: backup.smb == null
        ? const []
        : (await ref
                  .read(fileServerConnectionsRepositoryProvider)
                  .load(includePasswords: false))
              .whereType<SmbConnection>()
              .toList(),
    globals: state.requireValue,
  );

  Future<void> importConfiguration(
    ConfigurationImportPreview preview,
    Set<BackupSection> selected, {
    String? replacementAiKey,
  }) async {
    if (selected.isEmpty || !preview.backup.sections.containsAll(selected)) {
      throw const ConfigurationImportChanged();
    }
    final previous = state.requireValue;
    final importsAi = selected.contains(BackupSection.ai);
    final importsTmdb = selected.contains(BackupSection.tmdb);
    final importsDav = selected.contains(BackupSection.webdav);
    final importsSmb = selected.contains(BackupSection.smb);
    if (importsAi && previous.aiUrl != preview.previousAiUrl) {
      throw const ConfigurationImportChanged();
    }
    final globals = preview.mergeGlobals(
      previous,
      selected,
      replacementAiKey: replacementAiKey,
    );
    final connectionRepository = ref.read(connectionRepositoryProvider);
    final fileServers = ref.read(fileServerConnectionsRepositoryProvider);
    final settings = ref.read(settingsProvider.notifier);
    await _change(() async {
      if (importsDav || importsSmb) {
        final fresh = await previewConfiguration(preview.backup);
        if ((importsDav &&
                (fresh.skipped != preview.skipped ||
                    !listEquals(fresh.additions, preview.additions))) ||
            (importsSmb &&
                (fresh.smbSkipped != preview.smbSkipped ||
                    !listEquals(fresh.smbAdditions, preview.smbAdditions)))) {
          throw const ConfigurationImportChanged();
        }
      }
      final previousNaming = ref.read(settingsProvider);
      var attemptedGlobals = false;
      var attemptedNaming = false;
      try {
        if (importsAi || importsTmdb) {
          attemptedGlobals = true;
          await connectionRepository.save(globals, includeWebdav: false);
        }
        if (importsTmdb) {
          attemptedNaming = true;
          await settings.update(preview.mergeNaming);
        }
        if (importsDav || importsSmb) {
          await fileServers.insertImported([
            if (importsDav)
              for (final dav in preview.additions)
                WebDavConnection(
                  id: newConnectionId(),
                  name: dav.name,
                  url: dav.url,
                  username: dav.username,
                  password: dav.password ?? '',
                  useProxy: dav.proxy,
                ),
            if (importsSmb)
              for (final smb in preview.smbAdditions)
                smb.toConnection(id: newConnectionId()),
          ]);
        }
      } catch (_) {
        // The vault, preferences and SQLite cannot share one transaction.
        // Restore both previously attempted preference writes independently.
        var rollbackFailed = false;
        if (attemptedNaming) {
          try {
            await settings.update(
              (s) => s.copyWith(
                namingLanguage: previousNaming.namingLanguage,
                namingFormat: previousNaming.namingFormat,
              ),
            );
          } catch (_) {
            rollbackFailed = true;
          }
        }
        if (attemptedGlobals) {
          try {
            await connectionRepository.save(previous, includeWebdav: false);
          } catch (_) {
            rollbackFailed = true;
          }
        }
        if (rollbackFailed) {
          ref.invalidateSelf();
          throw const ConfigurationImportRollbackFailed();
        }
        rethrow;
      }
    }, globals: globals);
  }
}
