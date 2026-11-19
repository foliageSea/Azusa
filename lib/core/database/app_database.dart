import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

class AppDatabase {
  AppDatabase({required this.open});

  final Future<Database> Function() open;
  Future<Database>? _database;
  bool _closed = false;

  Future<Database> connection() {
    if (_closed) throw StateError('数据库已关闭');
    return _database ??= _initialize();
  }

  Future<Database> _initialize() async {
    Database? db;
    try {
      db = await open();
      db.execute('PRAGMA busy_timeout = 5000');
      db.execute('PRAGMA journal_mode = WAL');
      // Preparation records must be committed before any NAS write begins.
      db.execute('PRAGMA synchronous = FULL');
      db.execute('BEGIN IMMEDIATE');
      try {
        final version =
            db.select('PRAGMA user_version').single.values.single as int;
        if (version > 4) throw StateError('数据库版本过高');
        db.execute('''
          CREATE TABLE IF NOT EXISTS execution_history (
            id INTEGER PRIMARY KEY,
            record TEXT NOT NULL
          );
          CREATE TABLE IF NOT EXISTS ai_usage (
            id INTEGER PRIMARY KEY,
            started_at_us INTEGER NOT NULL,
            model TEXT NOT NULL,
            directory TEXT NOT NULL,
            succeeded INTEGER NOT NULL CHECK (succeeded IN (0, 1)),
            input_tokens INTEGER NOT NULL,
            output_tokens INTEGER NOT NULL,
            cached_tokens INTEGER NOT NULL,
            model_time_us INTEGER NOT NULL,
            responses INTEGER NOT NULL,
            missing_usage INTEGER NOT NULL CHECK (missing_usage IN (0, 1)),
            estimated_cost REAL,
            price_source TEXT
          );
          CREATE INDEX IF NOT EXISTS ai_usage_started_at
            ON ai_usage(started_at_us DESC);
          CREATE TABLE IF NOT EXISTS directory_favorites (
            id INTEGER PRIMARY KEY,
            endpoint TEXT NOT NULL,
            username TEXT NOT NULL,
            path TEXT NOT NULL,
            UNIQUE(endpoint, username, path)
          );
          CREATE TABLE IF NOT EXISTS webdav_connections (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            url TEXT NOT NULL,
            username TEXT NOT NULL,
            proxy_enabled INTEGER NOT NULL CHECK (proxy_enabled IN (0, 1)),
            secret_key TEXT NOT NULL
          );
          CREATE TABLE IF NOT EXISTS webdav_state (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            active_id TEXT,
            migrated INTEGER NOT NULL DEFAULT 0
          );
          INSERT OR IGNORE INTO webdav_state (id) VALUES (1);
          CREATE TABLE IF NOT EXISTS smb_connections (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            host TEXT NOT NULL,
            share TEXT NOT NULL,
            domain TEXT NOT NULL,
            username TEXT NOT NULL,
            secret_key TEXT NOT NULL
          );
          CREATE TABLE IF NOT EXISTS file_server_state (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            active_protocol TEXT CHECK (active_protocol IN ('webdav', 'smb')),
            active_id TEXT,
            CHECK ((active_protocol IS NULL) = (active_id IS NULL))
          );
          -- Seed the unified selection once; a v3 SMB selection must survive reopening.
          INSERT OR IGNORE INTO file_server_state (id, active_protocol, active_id)
            SELECT 1, CASE WHEN w.id IS NOT NULL THEN 'webdav' END, w.id
            FROM webdav_state s LEFT JOIN webdav_connections w ON w.id = s.active_id
            WHERE s.id = 1;
          -- Keep legacy WebDAV saves, selection and removal in sync. Clearing a
          -- WebDAV selection must not deactivate an active SMB connection.
          CREATE TRIGGER IF NOT EXISTS sync_webdav_active
          AFTER UPDATE OF active_id ON webdav_state
          BEGIN
            UPDATE file_server_state
              SET active_protocol = CASE WHEN NEW.active_id IS NOT NULL THEN 'webdav' END,
                  active_id = NEW.active_id
              WHERE id = 1 AND (NEW.active_id IS NOT NULL OR active_protocol = 'webdav');
          END;
          -- Public selection and removal accept a bare id, so ids are global.
          CREATE TRIGGER IF NOT EXISTS guard_webdav_connection_id
          BEFORE INSERT ON webdav_connections
          WHEN EXISTS (SELECT 1 FROM smb_connections WHERE id = NEW.id)
          BEGIN
            SELECT RAISE(ABORT, 'Duplicate file server connection id');
          END;
          CREATE TRIGGER IF NOT EXISTS guard_smb_connection_id
          BEFORE INSERT ON smb_connections
          WHEN EXISTS (SELECT 1 FROM webdav_connections WHERE id = NEW.id)
          BEGIN
            SELECT RAISE(ABORT, 'Duplicate file server connection id');
          END;
        ''');
        if (version < 4) {
          // Keep existing rows unknown. The active connection cannot tell us
          // where these historical operations actually ran.
          db.execute('''
            ALTER TABLE execution_history ADD COLUMN connection_id TEXT;
            ALTER TABLE execution_history ADD COLUMN server_name TEXT;
            ALTER TABLE execution_history ADD COLUMN server_protocol TEXT;
            PRAGMA user_version = 4;
          ''');
        }
        db.execute('COMMIT');
      } catch (_) {
        if (!db.autocommit) db.execute('ROLLBACK');
        rethrow;
      }
      return db;
    } catch (_) {
      db?.close();
      _database = null;
      rethrow;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final pending = _database;
    if (pending == null) return;
    Database db;
    try {
      db = await pending;
    } catch (_) {
      return;
    }
    db.close();
  }
}

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase(
    open: () async {
      final root = await getApplicationSupportDirectory();
      await root.create(recursive: true);
      return sqlite3.open('${root.path}${Platform.pathSeparator}azusa.sqlite3');
    },
  );
  ref.onDispose(() => unawaited(database.close()));
  return database;
});
