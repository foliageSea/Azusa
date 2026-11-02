import 'dart:io';

import 'package:azusa/core/database/app_database.dart';
import 'package:azusa/features/organizer/connections/connection_settings.dart';
import 'package:azusa/features/organizer/dav/directory_favorites.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final scope = nasScope(
    const ConnectionSettings(
      webdavUrl: 'https://nas.test/dav',
      username: 'user',
    ),
  );

  test('NAS 地址规范化，账号、根目录和服务器相互隔离', () async {
    expect(
      scope,
      nasScope(
        const ConnectionSettings(
          webdavUrl: 'https://NAS.test/dav/',
          username: 'user',
        ),
      ),
    );
    final database = AppDatabase(open: () async => sqlite3.openInMemory());
    final repo = DirectoryFavoritesRepository(database);
    addTearDown(database.close);
    await repo.add(scope, '/dav/series/');
    for (final other in [
      (endpoint: scope.endpoint, username: 'other'),
      (endpoint: 'https://other.test/dav/', username: 'user'),
      (endpoint: 'https://nas.test/other/', username: 'user'),
    ]) {
      expect(await repo.load(other), isEmpty);
      await repo.remove(
        other,
        other.endpoint.endsWith('/other/') ? '/other/series/' : '/dav/series/',
      );
    }
    expect(await repo.load(scope), ['/dav/series/']);
  });

  test('中文和百分号路径规范化去重，删除及重启保留', () async {
    final directory = await Directory('/tmp/opencode').createTemp('favorites-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/favorites.sqlite3';
    final database = AppDatabase(open: () async => sqlite3.open(path));
    final repo = DirectoryFavoritesRepository(database);
    addTearDown(database.close);
    await Future.wait([
      repo.add(scope, '/dav/%E5%89%A7%E9%9B%86'),
      repo.add(scope, '/dav/%E5%89%A7%E9%9B%86/'),
      repo.add(scope, '/dav/100%25/'),
    ]);
    expect((await repo.load(scope)).length, 2);
    await database.close();
    final reopenedDatabase = AppDatabase(open: () async => sqlite3.open(path));
    final reopened = DirectoryFavoritesRepository(reopenedDatabase);
    addTearDown(reopenedDatabase.close);
    expect(await reopened.load(scope), [
      '/dav/%E5%89%A7%E9%9B%86/',
      '/dav/100%25/',
    ]);
    await reopened.remove(scope, '/dav/%E5%89%A7%E9%9B%86/');
    expect(await reopened.load(scope), ['/dav/100%25/']);
    await reopened.add(scope, '/dav/');
    expect((await reopened.load(scope)).last, '/dav/');
  });

  test('拒绝根目录外和不安全路径', () async {
    final database = AppDatabase(open: () async => sqlite3.openInMemory());
    final repo = DirectoryFavoritesRepository(database);
    addTearDown(database.close);
    for (final path in [
      '/other/',
      '/dav-other/',
      '/dav/../',
      '/dav/%2f/',
      '/dav//test/',
    ]) {
      await expectLater(repo.add(scope, path), throwsFormatException);
    }
    expect(await repo.load(scope), isEmpty);
  });

  test('打开失败可重试，关闭后拒绝操作', () async {
    var fail = true;
    final database = AppDatabase(
      open: () async {
        if (fail) throw StateError('failed');
        return sqlite3.openInMemory();
      },
    );
    final repo = DirectoryFavoritesRepository(database);
    addTearDown(database.close);
    await expectLater(repo.load(scope), throwsStateError);
    fail = false;
    await repo.add(scope, '/dav/');
    await database.close();
    await expectLater(repo.load(scope), throwsStateError);
  });
}
