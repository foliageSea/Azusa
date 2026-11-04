import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/settings/settings.dart';
import '../organizer_state.dart';
import 'webdav_connections.dart';
import 'credential_vault.dart';

enum ProxyMode {
  direct('直连'),
  system('系统代理'),
  manual('手动代理');

  const ProxyMode(this.label);
  final String label;
}

class ConnectionSettings {
  const ConnectionSettings({
    this.connectionId,
    this.webdavUrl = '',
    this.username = '',
    this.aiUrl = 'https://api.openai.com/v1',
    this.model = '',
    this.proxyUrl = '',
    ProxyMode? proxyMode,
    this.proxyAi = true,
    this.proxyTmdb = true,
    this.proxyWebdav = false,
    this.webdavPassword = '',
    this.aiKey = '',
    this.tmdbToken = '',
    // Keep the public parameter separate from its legacy-aware backing field.
    // ignore: prefer_initializing_formals
  }) : _proxyMode = proxyMode;
  final ProxyMode? _proxyMode;
  final String? connectionId;
  // Preserve the behavior of callers and saved configurations predating modes.
  ProxyMode get proxyMode =>
      _proxyMode ??
      (proxyUrl.trim().isEmpty ? ProxyMode.direct : ProxyMode.manual);
  final String webdavUrl, username, aiUrl, model, proxyUrl;
  final String webdavPassword, aiKey, tmdbToken;
  final bool proxyAi, proxyTmdb, proxyWebdav;

  ConnectionSettings copyWith({
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
  }) => ConnectionSettings(
    connectionId: connectionId ?? this.connectionId,
    webdavUrl: webdavUrl ?? this.webdavUrl,
    username: username ?? this.username,
    aiUrl: aiUrl ?? this.aiUrl,
    model: model ?? this.model,
    proxyUrl: proxyUrl ?? this.proxyUrl,
    proxyMode: proxyMode ?? _proxyMode,
    webdavPassword: webdavPassword ?? this.webdavPassword,
    aiKey: aiKey ?? this.aiKey,
    tmdbToken: tmdbToken ?? this.tmdbToken,
    proxyAi: proxyAi ?? this.proxyAi,
    proxyTmdb: proxyTmdb ?? this.proxyTmdb,
    proxyWebdav: proxyWebdav ?? this.proxyWebdav,
  );
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
  if (Platform.isMacOS) {
    CredentialVault.forStorage(
      storage,
      legacyStorage: const FlutterSecureStorage(
        mOptions: CredentialVault.legacyMacOsOptions,
      ),
    );
  }
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
    final repository = ref.read(webDavConnectionsRepositoryProvider);
    final id = await repository.activeId();
    final connections = await repository.load(includePasswords: false);
    final active = connections.where((item) => item.id == id).firstOrNull;
    final cleared = ConnectionSettings(
      aiUrl: globals.aiUrl,
      model: globals.model,
      aiKey: globals.aiKey,
      tmdbToken: globals.tmdbToken,
      proxyUrl: globals.proxyUrl,
      proxyMode: globals.proxyMode,
      proxyAi: globals.proxyAi,
      proxyTmdb: globals.proxyTmdb,
    );
    return active == null
        ? cleared
        : (await repository.withPassword(active))
              .apply(cleared)
              .copyWith(connectionId: active.id);
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

  Future<void> saveConnection(WebDavConnection connection) => _change(
    () => ref.read(webDavConnectionsRepositoryProvider).save(connection),
    reset: connection.id == state.requireValue.connectionId,
  );

  Future<void> selectConnection(String id) async {
    if (id == state.requireValue.connectionId) return;
    await _change(
      () => ref.read(webDavConnectionsRepositoryProvider).select(id),
      reset: true,
    );
    await ref.read(organizerProvider.notifier).open(null);
  }

  Future<void> deleteConnection(String id) => _change(
    () => ref.read(webDavConnectionsRepositoryProvider).remove(id),
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
}
