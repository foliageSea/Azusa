import 'dart:io';

import 'package:azusa/core/database/app_database.dart';
import 'package:azusa/features/organizer/ai/ai_usage.dart';
import 'package:azusa/features/organizer/ai/ai_usage_history.dart';
import 'package:azusa/features/organizer/history/execution_history.dart';
import 'package:azusa/features/organizer/dav/directory_favorites.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('版本 1 数据库升级到版本 2 并保留已有记录', () async {
    final directory = await Directory('/tmp/opencode').createTemp('app-v1-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/azusa.sqlite3';
    final seed = sqlite3.open(path);
    seed.execute('''
      CREATE TABLE execution_history (id INTEGER PRIMARY KEY, record TEXT NOT NULL);
      INSERT INTO execution_history (record) VALUES ('existing');
      PRAGMA user_version = 1;
    ''');
    seed.close();
    final database = AppDatabase(open: () async => sqlite3.open(path));
    addTearDown(database.close);
    expect(await ExecutionHistoryRepository(database).load(), ['existing']);
    final db = await database.connection();
    expect(db.select('PRAGMA user_version').single.values.single, 2);
    db.execute(
      "INSERT INTO webdav_connections VALUES ('one', 'NAS', 'https://nas.test/', 'user', 0, 'secret-reference')",
    );
    db.execute("UPDATE webdav_state SET active_id = 'one', migrated = 1");
    await database.close();
    final reopened = AppDatabase(open: () async => sqlite3.open(path));
    addTearDown(reopened.close);
    final persisted = await reopened.connection();
    expect(
      persisted.select('SELECT name FROM webdav_connections').single['name'],
      'NAS',
    );
    expect(
      persisted
          .select('SELECT active_id FROM webdav_state')
          .single['active_id'],
      'one',
    );
  });

  test('三个 Repository 共用一个连接，记录及收藏重启后均保留', () async {
    final directory = await Directory('/tmp/opencode').createTemp('app-db-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/azusa.sqlite3';
    var opens = 0;
    final database = AppDatabase(
      open: () async {
        opens++;
        return sqlite3.open(path);
      },
    );
    addTearDown(database.close);
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(database)],
    );
    addTearDown(container.dispose);
    final history = container.read(executionHistoryRepositoryProvider);
    final usage = container.read(aiUsageRepositoryProvider);
    final favorites = container.read(directoryFavoritesRepositoryProvider);
    expect(history.database, same(usage.database));
    expect(history.database, same(favorites.database));
    const scope = (endpoint: 'https://nas.test/dav/', username: 'user');
    final record = AiUsageRecord(
      startedAt: DateTime.utc(2026, 11, 2),
      model: 'test',
      directory: '/dav/',
      usage: const AiUsage(inputTokens: 10, outputTokens: 2),
      succeeded: true,
    );
    await Future.wait([
      history.append('准备 mkdir'),
      usage.append(record),
      favorites.add(scope, '/dav/series/'),
    ]);
    expect(opens, 1);
    final db = await database.connection();
    expect(db.select('PRAGMA journal_mode').single.values.single, 'wal');
    expect(db.select('PRAGMA synchronous').single.values.single, 2);
    expect(db.select('PRAGMA user_version').single.values.single, 2);
    expect(
      db
          .select("SELECT name FROM sqlite_master WHERE type = 'table'")
          .map((row) => row['name']),
      unorderedEquals([
        'execution_history',
        'ai_usage',
        'directory_favorites',
        'webdav_connections',
        'webdav_state',
      ]),
    );
    await database.close();

    final reopened = AppDatabase(open: () async => sqlite3.open(path));
    addTearDown(reopened.close);
    expect(await ExecutionHistoryRepository(reopened).load(), ['准备 mkdir']);
    expect(
      (await AiUsageRepository(reopened).load()).single.toJson(),
      record.toJson(),
    );
    expect(await DirectoryFavoritesRepository(reopened).load(scope), [
      '/dav/series/',
    ]);
  });

  test('拒绝高版本数据库且不创建表', () async {
    final directory = await Directory('/tmp/opencode')
        .createTemp('app-version-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/azusa.sqlite3';
    final seed = sqlite3.open(path);
    seed.execute('PRAGMA user_version = 3');
    seed.close();
    final database = AppDatabase(open: () async => sqlite3.open(path));
    addTearDown(database.close);
    await expectLater(database.connection(), throwsStateError);
    final inspection = sqlite3.open(path);
    addTearDown(inspection.close);
    expect(inspection.select('PRAGMA user_version').single.values.single, 3);
    expect(
      inspection.select("SELECT name FROM sqlite_master WHERE type = 'table'"),
      isEmpty,
    );
  });

  test('初始化失败回滚建表并允许重试', () async {
    final directory = await Directory('/tmp/opencode').createTemp('app-retry-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/azusa.sqlite3';
    final seed = sqlite3.open(path);
    seed.execute('CREATE TABLE ai_usage (id INTEGER PRIMARY KEY)');
    seed.close();
    final database = AppDatabase(open: () async => sqlite3.open(path));
    addTearDown(database.close);
    await expectLater(database.connection(), throwsA(isA<SqliteException>()));
    final inspection = sqlite3.open(path);
    expect(inspection.select('PRAGMA user_version').single.values.single, 0);
    expect(
      inspection.select(
        "SELECT name FROM sqlite_master WHERE name = 'execution_history'",
      ),
      isEmpty,
    );
    inspection.execute('DROP TABLE ai_usage');
    inspection.close();
    expect(await ExecutionHistoryRepository(database).load(), isEmpty);
    expect(await AiUsageRepository(database).load(), isEmpty);
  });

  test('关闭未使用的数据库不会打开连接且禁止后续访问', () async {
    var opens = 0;
    final database = AppDatabase(
      open: () async {
        opens++;
        return sqlite3.openInMemory();
      },
    );
    await database.close();
    await database.close();
    expect(opens, 0);
    expect(database.connection, throwsStateError);
  });
}
