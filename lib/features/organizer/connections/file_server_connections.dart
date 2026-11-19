import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../core/database/app_database.dart';
import '../file_server/file_server_connection.dart';
import '../file_server/file_server_factory.dart';
import '../smb/smb_connection.dart';
import 'connection_settings.dart';
import 'webdav_connections.dart';

class FileServerConnectionsRepository {
  FileServerConnectionsRepository(
    AppDatabase database,
    FlutterSecureStorage secrets,
  ) : this.fromWebDav(WebDavConnectionsRepository(database, secrets));

  FileServerConnectionsRepository.fromWebDav(this._webDav);

  final WebDavConnectionsRepository _webDav;
  AppDatabase get database => _webDav.database;

  Future<List<FileServerConnection>> load({
    bool includePasswords = true,
  }) async {
    final webDav = await _webDav.load(includePasswords: includePasswords);
    final db = await database.connection();
    return [
      ...webDav,
      for (final row in db.select(
        'SELECT * FROM smb_connections ORDER BY rowid',
      ))
        _smbFromRow(row, includePasswords ? await _password(row) : ''),
    ];
  }

  Future<FileServerConnection?> active() async {
    final db = await database.connection();
    final state = db
        .select('SELECT active_protocol, active_id FROM file_server_state')
        .single;
    final id = state['active_id'];
    if (id == null) return null;
    switch (state['active_protocol']) {
      case WebDavConnection.protocolId:
        final webDav = await _webDav.load(includePasswords: false);
        final value = webDav
            .where((connection) => connection.id == id)
            .firstOrNull;
        return value == null ? null : _webDav.withPassword(value);
      case SmbConnection.protocolId:
        final rows = db.select('SELECT * FROM smb_connections WHERE id = ?', [
          id,
        ]);
        if (rows.isEmpty) return null;
        final row = rows.single;
        return _smbFromRow(row, await _password(row));
      default:
        throw StateError('不支持此文件服务器协议');
    }
  }

  Future<FileServerConnection> withPassword(FileServerConnection value) async {
    switch (value) {
      case WebDavConnection():
        return _webDav.withPassword(value);
      case SmbConnection():
        final db = await database.connection();
        final rows = db.select(
          'SELECT secret_key FROM smb_connections WHERE id = ?',
          [value.id],
        );
        if (rows.isEmpty) throw StateError('连接已不存在');
        return SmbConnection(
          id: value.id,
          name: value.name,
          host: value.host,
          share: value.share,
          domain: value.domain,
          username: value.username,
          password: await _password(rows.single),
        );
      default:
        throw const FormatException('不支持此文件服务器协议');
    }
  }

  Future<void> save(FileServerConnection value) async {
    switch (value) {
      case WebDavConnection():
        return _webDav.save(value);
      case SmbConnection():
        value.validate();
        final db = await database.connection();
        final key = _newSecretKey(value);
        final staged = {if (value.password.isNotEmpty) key: value.password};
        if (staged.isNotEmpty) await _webDav.credentials.update(staged);
        String? oldKey;
        try {
          _transaction(db, () {
            final rows = db.select(
              'SELECT secret_key FROM smb_connections WHERE id = ?',
              [value.id],
            );
            oldKey = rows.firstOrNull?['secret_key'] as String?;
            _writeSmb(db, value, key, upsert: true);
          });
        } catch (_) {
          await _cleanup(staged.keys);
          rethrow;
        }
        if (oldKey != null) await _cleanup([oldKey!]);
      default:
        throw const FormatException('不支持此文件服务器协议');
    }
  }

  Future<void> select(String id) async {
    final db = await database.connection();
    if (db.select('SELECT id FROM webdav_connections WHERE id = ?', [
      id,
    ]).isNotEmpty) {
      return _webDav.select(id);
    }
    _transaction(db, () {
      if (db.select('SELECT id FROM smb_connections WHERE id = ?', [
        id,
      ]).isEmpty) {
        throw StateError('连接已不存在');
      }
      db.execute(
        'UPDATE file_server_state SET active_protocol = ?, active_id = ? WHERE id = 1',
        [SmbConnection.protocolId, id],
      );
      // Legacy WebDAV callers must not treat a previously selected DAV as active.
      db.execute('UPDATE webdav_state SET active_id = NULL WHERE id = 1');
    });
  }

  Future<void> remove(String id) async {
    final db = await database.connection();
    final rows = db.select(
      'SELECT secret_key FROM smb_connections WHERE id = ?',
      [id],
    );
    if (rows.isEmpty) return _webDav.remove(id);
    _transaction(db, () {
      db.execute(
        'UPDATE file_server_state SET active_protocol = NULL, active_id = NULL WHERE id = 1 AND active_protocol = ? AND active_id = ?',
        [SmbConnection.protocolId, id],
      );
      db.execute('DELETE FROM smb_connections WHERE id = ?', [id]);
    });
    await _cleanup([rows.single['secret_key'] as String]);
  }

  /// Append all protocols in one transaction without changing the active server.
  Future<void> insertImported(List<FileServerConnection> connections) async {
    if (connections.isEmpty) return;
    final entries = <(FileServerConnection, String)>[];
    final staged = <String, String>{};
    for (final value in connections) {
      final String password;
      switch (value) {
        case WebDavConnection():
          if (value.name.trim().isEmpty) throw const FormatException('请输入连接名称');
          defaultFileServerFactory.validate(value);
          password = value.password;
        case SmbConnection():
          value.validate();
          password = value.password;
        default:
          throw const FormatException('不支持此文件服务器协议');
      }
      final key = _newSecretKey(value);
      entries.add((value, key));
      if (password.isNotEmpty) staged[key] = password;
    }
    final db = await database.connection();
    if (staged.isNotEmpty) await _webDav.credentials.update(staged);
    try {
      _transaction(db, () {
        for (final (value, key) in entries) {
          switch (value) {
            case WebDavConnection():
              insertWebDavConnectionRow(db, value, key);
            case SmbConnection():
              _writeSmb(db, value, key);
          }
        }
      });
    } catch (_) {
      await _cleanup(staged.keys);
      rethrow;
    }
  }

  String _newSecretKey(FileServerConnection value) =>
      'azusa.${value.protocol}.${value.id}.${newConnectionId()}';

  Future<String> _password(Row row) async =>
      await _webDav.credentials.read(row['secret_key'] as String) ?? '';

  Future<void> _cleanup(Iterable<String> keys) async {
    if (keys.isEmpty) return;
    try {
      await _webDav.credentials.update({for (final key in keys) key: null});
    } catch (_) {
      // Orphaned keys are never referenced; do not mask the transaction result.
    }
  }
}

SmbConnection _smbFromRow(Row row, String password) => SmbConnection(
  id: row['id'] as String,
  name: row['name'] as String,
  host: row['host'] as String,
  share: row['share'] as String,
  domain: row['domain'] as String,
  username: row['username'] as String,
  password: password,
);

void _writeSmb(
  Database db,
  SmbConnection value,
  String key, {
  bool upsert = false,
}) {
  const conflictClause = '''
    ON CONFLICT(id) DO UPDATE SET name=excluded.name, host=excluded.host,
      share=excluded.share, domain=excluded.domain, username=excluded.username,
      secret_key=excluded.secret_key
  ''';
  db.execute(
    '''
    INSERT INTO smb_connections (id, name, host, share, domain, username, secret_key)
    VALUES (?, ?, ?, ?, ?, ?, ?)
    ${upsert ? conflictClause : ''}
  ''',
    [
      value.id,
      value.name.trim(),
      value.host.trim(),
      value.share,
      value.domain.trim(),
      value.username.trim(),
      key,
    ],
  );
}

void _transaction(Database db, void Function() action) {
  db.execute('BEGIN IMMEDIATE');
  try {
    action();
    db.execute('COMMIT');
  } catch (_) {
    if (!db.autocommit) db.execute('ROLLBACK');
    rethrow;
  }
}

final fileServerConnectionsRepositoryProvider =
    Provider<FileServerConnectionsRepository>(
      (ref) => FileServerConnectionsRepository.fromWebDav(
        ref.watch(webDavConnectionsRepositoryProvider),
      ),
    );

final fileServerConnectionsProvider =
    FutureProvider<List<FileServerConnection>>((ref) async {
      await ref.watch(connectionSettingsProvider.future);
      return ref
          .watch(fileServerConnectionsRepositoryProvider)
          .load(includePasswords: false);
    });
