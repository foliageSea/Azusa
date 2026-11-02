import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/settings/settings.dart';

enum ProxyMode {
  direct('直连'),
  system('系统代理'),
  manual('手动代理');

  const ProxyMode(this.label);
  final String label;
}

class ConnectionSettings {
  const ConnectionSettings({
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
  // Preserve the behavior of callers and saved configurations predating modes.
  ProxyMode get proxyMode =>
      _proxyMode ??
      (proxyUrl.trim().isEmpty ? ProxyMode.direct : ProxyMode.manual);
  final String webdavUrl, username, aiUrl, model, proxyUrl;
  final String webdavPassword, aiKey, tmdbToken;
  final bool proxyAi, proxyTmdb, proxyWebdav;

  ConnectionSettings copyWith({
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
  static const _key = 'azusa.connections.v1';

  Future<ConnectionSettings> load() async {
    final raw = await preferences.getString(_key);
    final data = raw == null
        ? <String, dynamic>{}
        : jsonDecode(raw) as Map<String, dynamic>;
    return ConnectionSettings(
      webdavUrl: data['webdavUrl'] as String? ?? '',
      username: data['username'] as String? ?? '',
      aiUrl: data['aiUrl'] as String? ?? 'https://api.openai.com/v1',
      model: data['model'] as String? ?? '',
      proxyUrl: data['proxyUrl'] as String? ?? '',
      proxyMode: ProxyMode.values
          .where((mode) => mode.name == data['proxyMode'])
          .firstOrNull,
      proxyAi: data['proxyAi'] as bool? ?? true,
      proxyTmdb: data['proxyTmdb'] as bool? ?? true,
      proxyWebdav: data['proxyWebdav'] as bool? ?? false,
      webdavPassword: await secrets.read(key: 'azusa.webdavPassword') ?? '',
      aiKey: await secrets.read(key: 'azusa.aiKey') ?? '',
      tmdbToken: await secrets.read(key: 'azusa.tmdbToken') ?? '',
    );
  }

  Future<void> save(ConnectionSettings value) async {
    await secrets.write(
      key: 'azusa.webdavPassword',
      value: value.webdavPassword,
    );
    await secrets.write(key: 'azusa.aiKey', value: value.aiKey);
    await secrets.write(key: 'azusa.tmdbToken', value: value.tmdbToken);
    await preferences.setString(
      _key,
      jsonEncode({
        'webdavUrl': value.webdavUrl,
        'username': value.username,
        'aiUrl': value.aiUrl,
        'model': value.model,
        'proxyUrl': value.proxyUrl,
        'proxyMode': value.proxyMode.name,
        'proxyAi': value.proxyAi,
        'proxyTmdb': value.proxyTmdb,
        'proxyWebdav': value.proxyWebdav,
      }),
    );
  }
}

final connectionRepositoryProvider = Provider(
  (ref) => ConnectionRepository(
    ref.watch(preferencesProvider),
    const FlutterSecureStorage(),
  ),
);
final connectionSettingsProvider =
    AsyncNotifierProvider<ConnectionSettingsController, ConnectionSettings>(
      ConnectionSettingsController.new,
    );

class ConnectionSettingsController extends AsyncNotifier<ConnectionSettings> {
  @override
  Future<ConnectionSettings> build() =>
      ref.read(connectionRepositoryProvider).load();

  Future<void> save(ConnectionSettings value) async {
    await ref.read(connectionRepositoryProvider).save(value);
    state = AsyncData(value);
  }
}
