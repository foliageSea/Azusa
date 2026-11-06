import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// One OS credential item; logical keys inside it are never stored in SQLite.
class CredentialVault {
  CredentialVault._(this.storage);

  static const storageKey = 'azusa.credentials.v1';
  static const macOsOptions = MacOsOptions(
    accountName: 'com.foliage.azusa.credentials',
    label: 'Azusa 凭据',
    usesDataProtectionKeychain: false,
  );
  static final _instances = Expando<CredentialVault>();

  static CredentialVault forStorage(FlutterSecureStorage storage) =>
      _instances[storage] ??= CredentialVault._(storage);

  final FlutterSecureStorage storage;
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

    final values = <String, String>{};
    await storage.write(key: storageKey, value: _encode(values));
    return _values = values;
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
