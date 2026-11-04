import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/database/app_database.dart';
import 'connection_settings.dart';
import '../dav/webdav.dart';

String newConnectionId() => List.generate(
  16,
  (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();

class WebDavConnection {
  const WebDavConnection({
    required this.id,
    required this.name,
    required this.url,
    this.username = '',
    this.password = '',
    this.useProxy = false,
  });

  final String id, name, url, username, password;
  final bool useProxy;

  ConnectionSettings apply(ConnectionSettings settings) => settings.copyWith(
    webdavUrl: url,
    username: username,
    webdavPassword: password,
    proxyWebdav: useProxy,
  );
}

class WebDavConnectionsRepository {
  WebDavConnectionsRepository(this.database, this.secrets);
  final AppDatabase database;
  final FlutterSecureStorage secrets;

  Future<bool> migrated() async =>
      (await database.connection())
          .select('SELECT migrated FROM webdav_state')
          .single['migrated'] ==
      1;

  Future<void> initialize(ConnectionSettings legacy) async {
    final db = await database.connection();
    if (await migrated()) {
      await _cleanup('azusa.webdavPassword');
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

  Future<List<WebDavConnection>> load() async {
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
          password: await secrets.read(key: row['secret_key'] as String) ?? '',
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
    db.execute('UPDATE webdav_state SET active_id = ? WHERE id = 1', [id]);
  }

  Future<void> save(
    WebDavConnection value, {
    bool activate = false,
    bool markMigrated = false,
  }) async {
    if (value.name.trim().isEmpty) throw const FormatException('请输入连接名称');
    final validation = WebDavClient(value.apply(const ConnectionSettings()));
    validation.close();
    final db = await database.connection();
    final previous = db.select(
      'SELECT secret_key FROM webdav_connections WHERE id = ?',
      [value.id],
    );
    // Versioned secrets keep the previous password intact until SQLite commits.
    final key = 'azusa.webdav.${value.id}.${newConnectionId()}';
    await secrets.write(key: key, value: value.password);
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
        db.execute('ROLLBACK');
        rethrow;
      }
    } catch (_) {
      await _cleanup(key);
      rethrow;
    }
    if (previous.isNotEmpty) {
      await _cleanup(previous.single['secret_key'] as String);
    }
  }

  Future<void> _cleanup(String key) async {
    // A cleanup failure must not turn a committed save into an apparent failure.
    try {
      await secrets.delete(key: key);
    } catch (_) {
      /* Orphaned, never referenced. */
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
      db.execute('ROLLBACK');
      rethrow;
    }
    if (rows.isNotEmpty) await _cleanup(rows.single['secret_key'] as String);
  }
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
  return ref.watch(webDavConnectionsRepositoryProvider).load();
});
