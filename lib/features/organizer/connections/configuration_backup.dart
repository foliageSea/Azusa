import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../../../core/settings/naming_format.dart';
import '../../../core/settings/naming_language.dart';
import '../file_server/file_server_paths.dart';
import '../smb/smb_connection.dart';
import 'http_clients.dart';

enum BackupSection { webdav, smb, tmdb, ai }

typedef BackupDav = ({
  String name,
  String url,
  String username,
  bool proxy,
  String? password,
});
typedef BackupSmb = ({
  String name,
  String host,
  String share,
  String domain,
  String username,
  String? password,
});

extension BackupSmbConnection on BackupSmb {
  SmbConnection toConnection({required String id}) => SmbConnection(
    id: id,
    name: name,
    host: host,
    share: share,
    domain: domain,
    username: username,
    password: password ?? '',
  );
}

typedef BackupAi = ({String url, String model, bool proxy, String? key});
typedef BackupTmdb = ({
  NamingLanguage language,
  NamingFormat format,
  bool proxy,
  String? token,
});

typedef BackupDavIdentity = ({String endpoint, String username});

BackupDavIdentity backupDavIdentity(String url, String username) {
  final uri = validatedHttpUrl(url, allowHttp: true);
  final path = canonicalFileServerPath(uri.path.isEmpty ? '/' : uri.path);
  return (
    endpoint: '${uri.origin}${path.endsWith('/') ? path : '$path/'}',
    username: username.trim(),
  );
}

class ConfigurationBackup {
  ConfigurationBackup({
    List<BackupDav>? webdav,
    List<BackupSmb>? smb,
    this.tmdb,
    this.ai,
  }) : webdav = webdav == null ? null : List.unmodifiable(webdav),
       smb = smb == null ? null : List.unmodifiable(smb);

  final List<BackupDav>? webdav;
  final List<BackupSmb>? smb;
  final BackupTmdb? tmdb;
  final BackupAi? ai;

  Set<BackupSection> get sections => {
    if (webdav != null) BackupSection.webdav,
    if (smb != null) BackupSection.smb,
    if (tmdb != null) BackupSection.tmdb,
    if (ai != null) BackupSection.ai,
  };

  bool hasCredentials(BackupSection section) => switch (section) {
    BackupSection.webdav => webdav?.any((dav) => dav.password != null) ?? false,
    BackupSection.smb => smb?.any((item) => item.password != null) ?? false,
    BackupSection.tmdb => tmdb?.token != null,
    BackupSection.ai => ai?.key != null,
  };

  Map<String, Object> _toJson() => {
    if (webdav case final items?)
      'webdav': [
        for (final dav in items)
          {
            'name': dav.name,
            'url': dav.url,
            'username': dav.username,
            'proxy': dav.proxy,
            'password': ?dav.password,
          },
      ],
    if (smb case final items?)
      'smb': [
        for (final item in items)
          {
            'name': item.name,
            'host': item.host,
            'share': item.share,
            'domain': item.domain,
            'username': item.username,
            'password': ?item.password,
          },
      ],
    if (tmdb case final tmdb?)
      'tmdb': {
        'language': tmdb.language.code,
        'format': tmdb.format.name,
        'proxy': tmdb.proxy,
        'token': ?tmdb.token,
      },
    if (ai case final ai?)
      'ai': {
        'url': ai.url,
        'model': ai.model,
        'proxy': ai.proxy,
        'key': ?ai.key,
      },
  };

  factory ConfigurationBackup._parse(
    Object? value, {
    required bool encrypted,
    required int version,
  }) {
    final data = _object(value, {
      'webdav',
      if (version == ConfigurationBackupCodec._smbVersion) 'smb',
      'tmdb',
      'ai',
    });
    List<BackupDav>? webdav;
    List<BackupSmb>? smb;
    BackupTmdb? tmdb;
    BackupAi? ai;
    if (data.containsKey('webdav')) {
      final items = data['webdav'];
      if (items is! List) _invalid();
      webdav = items.map((item) {
        final dav = _object(item, {
          'name',
          'url',
          'username',
          'proxy',
          if (encrypted) 'password',
        });
        final name = _read<String>(dav, 'name').trim();
        final url = _read<String>(dav, 'url').trim();
        final username = _read<String>(dav, 'username').trim();
        if (name.isEmpty) _invalid();
        backupDavIdentity(url, username);
        return (
          name: name,
          url: url,
          username: username,
          proxy: _read<bool>(dav, 'proxy'),
          password: _secret(dav, 'password'),
        );
      }).toList();
    }
    if (data.containsKey('smb')) {
      final items = data['smb'];
      if (items is! List) _invalid();
      smb = items.map((item) {
        final fields = _object(item, {
          'name',
          'host',
          'share',
          'domain',
          'username',
          if (encrypted) 'password',
        });
        final value = (
          name: _read<String>(fields, 'name'),
          host: _read<String>(fields, 'host'),
          share: _read<String>(fields, 'share'),
          domain: _read<String>(fields, 'domain'),
          username: _read<String>(fields, 'username'),
          password: _secret(fields, 'password'),
        );
        try {
          value.toConnection(id: 'backup').validate();
        } on FormatException {
          _invalid();
        } on ArgumentError {
          _invalid();
        }
        return (
          name: value.name.trim(),
          host: value.host.trim(),
          share: value.share,
          domain: value.domain.trim(),
          username: value.username.trim(),
          password: value.password,
        );
      }).toList();
    }
    if (data.containsKey('tmdb')) {
      final item = _object(data['tmdb'], {
        'language',
        'format',
        'proxy',
        if (encrypted) 'token',
      });
      tmdb = (
        language:
            NamingLanguage.values
                .where((v) => v.code == item['language'])
                .firstOrNull ??
            _invalid(),
        format:
            NamingFormat.values
                .where((v) => v.name == item['format'])
                .firstOrNull ??
            _invalid(),
        proxy: _read<bool>(item, 'proxy'),
        token: _secret(item, 'token'),
      );
    }
    if (data.containsKey('ai')) {
      final item = _object(data['ai'], {
        'url',
        'model',
        'proxy',
        if (encrypted) 'key',
      });
      final url = _read<String>(item, 'url').trim();
      if (url.isNotEmpty) validatedHttpUrl(url, allowHttp: true);
      ai = (
        url: url,
        model: _read<String>(item, 'model').trim(),
        proxy: _read<bool>(item, 'proxy'),
        key: _secret(item, 'key'),
      );
    }
    if (data.isEmpty) _invalid();
    return ConfigurationBackup(webdav: webdav, smb: smb, tmdb: tmdb, ai: ai);
  }
}

enum BackupProblem {
  invalid,
  unsupported,
  tooLarge,
  passphraseRequired,
  unlockFailed,
}

class BackupException implements Exception {
  const BackupException(this.problem);
  final BackupProblem problem;
}

Never _invalid() => throw const BackupException(BackupProblem.invalid);

Map<String, dynamic> _object(Object? value, Set<String> keys) {
  if (value is! Map<String, dynamic> || !value.keys.every(keys.contains)) {
    _invalid();
  }
  return value;
}

T _read<T>(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is! T) _invalid();
  return value;
}

String? _secret(Map<String, dynamic> data, String key) {
  if (!data.containsKey(key)) return null;
  final value = _read<String>(data, key);
  return value.isEmpty ? null : value;
}

class ConfigurationBackupCodec {
  static const maxBytes = 2 * 1024 * 1024;
  static const minPassphraseLength = 12;
  static const _format = 'azusa.configuration';
  static const _legacyVersion = 1;
  static const _smbVersion = 2;
  static const _cipher = 'pbkdf2-sha256-600000/aes-256-gcm';
  static List<int> _aad(int version) =>
      utf8.encode('$_format:$version:$_cipher');

  Future<Uint8List> encode(ConfigurationBackup backup, {String? passphrase}) =>
      compute(_encode, (backup, passphrase));

  bool isEncrypted(Uint8List bytes) => _envelope(bytes).containsKey('cipher');

  Future<ConfigurationBackup> decode(Uint8List bytes, {String? passphrase}) =>
      compute(_decode, (bytes, passphrase));

  static Map<String, dynamic> _envelope(Uint8List bytes) {
    if (bytes.length > maxBytes) {
      throw const BackupException(BackupProblem.tooLarge);
    }
    final Object? raw;
    try {
      raw = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      _invalid();
    }
    if (raw is! Map<String, dynamic> || raw['format'] != _format) _invalid();
    final version = raw['version'];
    if (version is! int ||
        (version != _legacyVersion && version != _smbVersion)) {
      throw const BackupException(BackupProblem.unsupported);
    }
    if (raw.containsKey('cipher')) {
      if (raw['cipher'] != _cipher) {
        throw const BackupException(BackupProblem.unsupported);
      }
      return _object(raw, {'format', 'version', 'cipher', 'salt', 'box'});
    }
    return _object(raw, {'format', 'version', 'data'});
  }

  static Future<SecretKey> _key(String passphrase, List<int> salt) => Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 600000,
    bits: 256,
  ).deriveKeyFromPassword(password: passphrase, nonce: salt);

  static Future<Uint8List> _encode((ConfigurationBackup, String?) input) async {
    final (backup, passphrase) = input;
    final data = backup._toJson();
    final encrypted = passphrase != null;
    final version = backup.smb == null ? _legacyVersion : _smbVersion;
    ConfigurationBackup._parse(data, encrypted: encrypted, version: version);
    final envelope = <String, Object>{'format': _format, 'version': version};
    if (encrypted) {
      if (passphrase.trim().runes.length < minPassphraseLength) {
        throw const BackupException(BackupProblem.passphraseRequired);
      }
      final random = Random.secure();
      final salt = List.generate(32, (_) => random.nextInt(256));
      final box = await AesGcm.with256bits().encrypt(
        utf8.encode(jsonEncode(data)),
        secretKey: await _key(passphrase, salt),
        aad: _aad(version),
      );
      envelope.addAll({
        'cipher': _cipher,
        'salt': base64Encode(salt),
        'box': base64Encode(box.concatenation()),
      });
    } else {
      envelope['data'] = data;
    }
    final bytes = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(envelope),
    );
    if (bytes.length > maxBytes) {
      throw const BackupException(BackupProblem.tooLarge);
    }
    return bytes;
  }

  static Future<ConfigurationBackup> _decode((Uint8List, String?) input) async {
    final (bytes, passphrase) = input;
    final envelope = _envelope(bytes);
    final version = _read<int>(envelope, 'version');
    final encrypted = envelope.containsKey('cipher');
    try {
      Object? data = envelope['data'];
      if (encrypted) {
        final salt = base64Decode(_read<String>(envelope, 'salt'));
        final packed = base64Decode(_read<String>(envelope, 'box'));
        if (salt.length != 32 || packed.length <= 28) _invalid();
        if (passphrase == null || passphrase.isEmpty) {
          throw const BackupException(BackupProblem.passphraseRequired);
        }
        final cipher = AesGcm.with256bits();
        final box = SecretBox.fromConcatenation(
          packed,
          nonceLength: 12,
          macLength: 16,
        );
        final clear = await cipher.decrypt(
          box,
          secretKey: await _key(passphrase, salt),
          aad: _aad(version),
        );
        data = jsonDecode(utf8.decode(clear));
      }
      return ConfigurationBackup._parse(
        data,
        encrypted: encrypted,
        version: version,
      );
    } on SecretBoxAuthenticationError {
      throw const BackupException(BackupProblem.unlockFailed);
    } on FormatException {
      // FormatException may contain input data; never propagate it.
      _invalid();
    } on ArgumentError {
      _invalid();
    }
  }
}
