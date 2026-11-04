import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// One OS credential item; logical keys inside it are never stored in SQLite.
class CredentialVault {
  CredentialVault._(this.storage, this.legacyStorage);

  static const storageKey = 'azusa.credentials.v1';
  static const macOsOptions = MacOsOptions(
    accountName: 'com.foliage.azusa.credentials',
    label: 'Azusa 凭据',
    usesDataProtectionKeychain: false,
  );
  static const legacyMacOsOptions = MacOsOptions(
    usesDataProtectionKeychain: false,
  );
  static const _globalKeys = [
    'azusa.webdavPassword',
    'azusa.aiKey',
    'azusa.tmdbToken',
  ];
  static final _instances = Expando<CredentialVault>();

  static CredentialVault forStorage(
    FlutterSecureStorage storage, {
    FlutterSecureStorage? legacyStorage,
  }) => _instances[storage] ??= CredentialVault._(
    storage,
    legacyStorage ?? storage,
  );

  final FlutterSecureStorage storage;
  final FlutterSecureStorage legacyStorage;
  Future<Iterable<String>> Function()? legacyWebDavKeys;
  Future<Map<String, String>>? _loaded;
  Map<String, String>? _values;
  Future<void> _pending = Future.value();

  // Keep a failed authorization cached too: rebuilding a provider must not
  // silently show another system prompt. Only an explicit retry clears it.
  void retryFailedLoad() {
    if (_values == null) _loaded = null;
  }

  Future<Map<String, String>> _load() => _loaded ??= _initialize();

  Map<String, String> _decode(String raw) {
    // jsonDecode's FormatException includes the source text. Never expose a
    // credential payload in UI errors or logs, even when the vault is corrupt.
    final dynamic data;
    try {
      data = jsonDecode(raw);
    } on FormatException {
      throw const FormatException('凭据仓库格式无效');
    }
    if (data is! Map<String, dynamic> ||
        data['version'] != 1 ||
        data['values'] is! Map<String, dynamic>) {
      throw const FormatException('凭据仓库格式无效');
    }
    final values = <String, String>{};
    for (final entry in (data['values'] as Map<String, dynamic>).entries) {
      if (entry.value is! String) throw const FormatException('凭据仓库格式无效');
      values[entry.key] = entry.value as String;
    }
    return values;
  }

  String _encode(Map<String, String> values) =>
      jsonEncode({'version': 1, 'values': values});

  Future<Map<String, String>> _initialize() async {
    final raw = await storage.read(key: storageKey);
    if (raw != null) return _values = _decode(raw);

    // A previous build may already have a consolidated vault in the plugin's
    // default service. Move it intact before considering individual old keys.
    if (!identical(storage, legacyStorage)) {
      final legacy = await legacyStorage.read(key: storageKey);
      if (legacy != null) {
        final values = _decode(legacy);
        await _writeAndVerify(legacy);
        await _cleanupLegacy(storageKey);
        return _values = values;
      }
    }

    final keys = {..._globalKeys, ...?await legacyWebDavKeys?.call()};
    final values = <String, String>{};
    for (final key in keys) {
      final value = await legacyStorage.read(key: key);
      if (value != null) values[key] = value;
    }
    final encoded = _encode(values);
    await _writeAndVerify(encoded);
    for (final key in values.keys) {
      await _cleanupLegacy(key);
    }
    return _values = values;
  }

  Future<void> _writeAndVerify(String encoded) async {
    await storage.write(key: storageKey, value: encoded);
    // No legacy data is deleted until the entire vault has been verified.
    final verified = await storage.read(key: storageKey);
    if (verified != encoded) throw StateError('凭据仓库迁移验证失败');
    _decode(verified!);
  }

  Future<void> _cleanupLegacy(String key) async {
    try {
      await legacyStorage.delete(key: key);
    } catch (_) {
      // Never retry automatically on each launch: cleanup may prompt again.
    }
  }

  Future<String?> read(String key) async {
    await _load();
    return _values![key];
  }

  Future<void> write(String key, String? value) => update({key: value});

  /// Serialize read-modify-write operations so concurrent service updates cannot
  /// overwrite each other. Publish the cache only after OS storage succeeds.
  Future<void> update(Map<String, String?> changes) {
    final snapshot = Map<String, String?>.of(changes);
    final operation = _pending.then((_) async {
      await _load();
      if (snapshot.entries.every(
        (entry) => _values![entry.key] == entry.value,
      )) {
        return;
      }
      final next = Map<String, String>.of(_values!);
      for (final entry in snapshot.entries) {
        if (entry.value == null) {
          next.remove(entry.key);
        } else {
          next[entry.key] = entry.value!;
        }
      }
      await storage.write(key: storageKey, value: _encode(next));
      _values = next;
    });
    _pending = operation.catchError((Object _, StackTrace _) {});
    return operation;
  }
}
