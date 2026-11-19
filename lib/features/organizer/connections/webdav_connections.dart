import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../core/database/app_database.dart';
import '../file_server/file_server_connection.dart';
import '../file_server/file_server_factory.dart';
import 'connection_settings.dart';
import 'credential_vault.dart';

String newConnectionId() => List.generate(
  16,
  (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();

class WebDavConnection implements FileServerConnection {
  const WebDavConnection({
    required this.id,
    required this.name,
    required this.url,
    this.username = '',
    this.password = '',
    this.useProxy = false,
  });

  @override
  final String id;
  @override
  final String name;
  static const protocolId = 'webdav';

  @override
  String get protocol => protocolId;

  final String url, username, password;
  final bool useProxy;

  ConnectionSettings apply(ConnectionSettings settings) =>
      settings.copyWith(fileServerConnection: this);
}

class WebDavConnectionsRepository {
  WebDavConnectionsRepository(this.database, this.secrets);
  final AppDatabase database;
  final FlutterSecureStorage secrets;
  CredentialVault get credentials => CredentialVault.forStorage(secrets);

  Future<bool> migrated() async =>
      (await database.connection())
          .select('SELECT migrated FROM webdav_state')
          .single['migrated'] ==
      1;

  Future<void> initialize(ConnectionSettings legacy) async {
    final db = await database.connection();
    if (await migrated()) {
      return;
    }
    if (legacy.webdavUrl.trim().isNotEmpty) {
      // A stable ID makes an interrupted migration safe to repeat.
      await save(
        WebDavConnection(
          id: 'legacy',
          name: Uri.tryParse(legacy.webdavUrl)?.host ?? 'WebDAV',
          url: legacy.webdavUrl,
          username: legacy.username,
          password: legacy.webdavPassword,
          useProxy: legacy.proxyWebdav,
        ),
        activate: true,
        markMigrated: true,
      );
      await _cleanup('azusa.webdavPassword');
      return;
    }
    db.execute('UPDATE webdav_state SET migrated = 1 WHERE id = 1');
  }

  Future<WebDavConnection> withPassword(WebDavConnection value) async {
    final db = await database.connection();
    final rows = db.select(
      'SELECT secret_key FROM webdav_connections WHERE id = ?',
      [value.id],
    );
    if (rows.isEmpty) throw StateError('连接已不存在');
    return WebDavConnection(
      id: value.id,
      name: value.name,
      url: value.url,
      username: value.username,
      useProxy: value.useProxy,
      password:
          await credentials.read(rows.single['secret_key'] as String) ?? '',
    );
  }

  Future<List<WebDavConnection>> load({bool includePasswords = true}) async {
    final db = await database.connection();
    final result = <WebDavConnection>[];
    for (final row in db.select(
      'SELECT * FROM webdav_connections ORDER BY rowid',
    )) {
      result.add(
        WebDavConnection(
          id: row['id'] as String,
          name: row['name'] as String,
          url: row['url'] as String,
          username: row['username'] as String,
          useProxy: row['proxy_enabled'] == 1,
          password: includePasswords
              ? await credentials.read(row['secret_key'] as String) ?? ''
              : '',
        ),
      );
    }
    return result;
  }

  Future<String?> activeId() async =>
      (await database.connection())
              .select('SELECT active_id FROM webdav_state')
              .single['active_id']
          as String?;

  Future<void> select(String? id) async {
    final db = await database.connection();
    if (id != null &&
        db.select('SELECT id FROM webdav_connections WHERE id = ?', [
          id,
        ]).isEmpty) {
      throw StateError('连接已不存在');
    }
    // The v3 trigger updates the unified selection in the same statement.
    db.execute('UPDATE webdav_state SET active_id = ? WHERE id = 1', [id]);
  }

  Future<void> save(
    WebDavConnection value, {
    bool activate = false,
    bool markMigrated = false,
  }) async {
    if (value.name.trim().isEmpty) throw const FormatException('请输入连接名称');
    defaultFileServerFactory.validate(value);
    final db = await database.connection();
    final previous = db.select(
      'SELECT secret_key FROM webdav_connections WHERE id = ?',
      [value.id],
    );
    // Version logical references inside the single vault, not OS keychain items.
    // This preserves the previous password until SQLite commits.
    final oldKey = previous.isEmpty
        ? null
        : previous.single['secret_key'] as String;
    final unchanged =
        oldKey != null && await credentials.read(oldKey) == value.password;
    final key = unchanged
        ? oldKey
        : 'azusa.webdav.${value.id}.${newConnectionId()}';
    if (!unchanged) await credentials.write(key, value.password);
    try {
      db.execute('BEGIN IMMEDIATE');
      try {
        db.execute(
          '''
          INSERT INTO webdav_connections (id, name, url, username, proxy_enabled, secret_key)
          VALUES (?, ?, ?, ?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET name=excluded.name, url=excluded.url,
            username=excluded.username, proxy_enabled=excluded.proxy_enabled,
            secret_key=excluded.secret_key
        ''',
          [
            value.id,
            value.name.trim(),
            value.url.trim(),
            value.username.trim(),
            value.useProxy ? 1 : 0,
            key,
          ],
        );
        if (activate) {
          db.execute('UPDATE webdav_state SET active_id = ? WHERE id = 1', [
            value.id,
          ]);
        }
        if (markMigrated) {
          db.execute('UPDATE webdav_state SET migrated = 1 WHERE id = 1');
        }
        db.execute('COMMIT');
      } catch (_) {
        if (!db.autocommit) db.execute('ROLLBACK');
        rethrow;
      }
    } catch (_) {
      if (!unchanged) await _cleanup(key);
      rethrow;
    }
    if (previous.isNotEmpty && !unchanged) {
      await _cleanup(previous.single['secret_key'] as String);
    }
  }

  Future<void> _cleanup(String key) async {
    // A cleanup failure must not turn a committed save into an apparent failure.
    try {
      await credentials.write(key, null);
    } catch (_) {
      /* Orphaned, never referenced. */
    }
  }

  /// Append a validated import as one SQLite transaction, without changing the
  /// active connection. Stage all new credentials before creating references.
  Future<void> insertImported(List<WebDavConnection> connections) async {
    if (connections.isEmpty) return;
    final db = await database.connection();
    final entries = [
      for (final connection in connections)
        (connection, 'azusa.webdav.${connection.id}.${newConnectionId()}'),
    ];
    final staged = {
      for (final (value, key) in entries)
        if (value.password.isNotEmpty) key: value.password,
    };
    if (staged.isNotEmpty) await credentials.update(staged);
    try {
      db.execute('BEGIN IMMEDIATE');
      try {
        for (final (value, key) in entries) {
          insertWebDavConnectionRow(db, value, key);
        }
        db.execute('COMMIT');
      } catch (_) {
        if (!db.autocommit) db.execute('ROLLBACK');
        rethrow;
      }
    } catch (_) {
      try {
        await credentials.update({for (final key in staged.keys) key: null});
      } catch (_) {
        // Unreferenced keys do not expose or alter existing connections.
      }
      rethrow;
    }
  }

  Future<void> remove(String id) async {
    final db = await database.connection();
    final rows = db.select(
      'SELECT secret_key FROM webdav_connections WHERE id = ?',
      [id],
    );
    db.execute('BEGIN IMMEDIATE');
    try {
      db.execute(
        'UPDATE webdav_state SET active_id = NULL WHERE active_id = ?',
        [id],
      );
      db.execute('DELETE FROM webdav_connections WHERE id = ?', [id]);
      db.execute('COMMIT');
    } catch (_) {
      if (!db.autocommit) db.execute('ROLLBACK');
      rethrow;
    }
    if (rows.isNotEmpty) await _cleanup(rows.single['secret_key'] as String);
  }
}

/// Insert a WebDAV row using the caller's transaction and staged credential.
void insertWebDavConnectionRow(
  Database db,
  WebDavConnection value,
  String key,
) {
  db.execute(
    '''
    INSERT INTO webdav_connections
      (id, name, url, username, proxy_enabled, secret_key)
    VALUES (?, ?, ?, ?, ?, ?)
    ''',
    [
      value.id,
      value.name,
      value.url,
      value.username,
      value.useProxy ? 1 : 0,
      key,
    ],
  );
}

final webDavConnectionsRepositoryProvider = Provider(
  (ref) => WebDavConnectionsRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(connectionRepositoryProvider).secrets,
  ),
);

final webDavConnectionsProvider = FutureProvider<List<WebDavConnection>>((
  ref,
) async {
  await ref.watch(connectionSettingsProvider.future);
  return ref
      .watch(webDavConnectionsRepositoryProvider)
      .load(includePasswords: false);
});
