import 'dart:io';

import 'package:azusa/core/database/app_database.dart';
import 'package:azusa/features/organizer/connections/connection_settings.dart';
import 'package:azusa/features/organizer/history/execution_history.dart';
import 'package:azusa/features/organizer/organizer_state.dart';
import 'package:azusa/features/organizer/rename_plan.dart';
import 'package:azusa/features/organizer/dav/webdav.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

const records = [
  '2026-11-02 09:48:54.720825 准备重命名 /dav/旧名称.mkv → /dav/新名称.mkv',
  '2026-11-02 09:48:54.738497 完成重命名 /dav/旧名称.mkv → /dav/新名称.mkv',
  '旧格式记录',
];

class ReadyOrganizer extends OrganizerController {
  @override
  ConnectionSettings get config =>
      const ConnectionSettings(webdavUrl: 'https://nas.test/dav/');

  @override
  OrganizerState build() => const OrganizerState(
    directory: '/dav/',
    entries: [DavEntry('/dav/old.mkv', false)],
    plan: [RenameItem(source: '/dav/old.mkv', targetName: 'new.mkv')],
  );
}

class RecordingDav extends WebDavClient {
  RecordingDav()
    : super(const ConnectionSettings(webdavUrl: 'https://nas.test/dav/'));
  int writes = 0;
  @override
  Future<List<DavEntry>> list(String path) async => [];
  @override
  Future<DavEntry?> stat(String path) async =>
      path == '/dav/old.mkv' ? const DavEntry('/dav/old.mkv', false) : null;
  @override
  Future<void> mkdir(String path) async {
    writes++;
  }

  @override
  Future<void> move(String from, String to, {String? etag}) async {
    writes++;
  }
}

void main() {
  test('SQLite 重启及并发追加保留原文、顺序和重复记录', () async {
    final directory = await Directory('/tmp/opencode')
        .createTemp('execution-history-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/history.sqlite3';
    final database = AppDatabase(open: () async => sqlite3.open(path));
    final repo = ExecutionHistoryRepository(database);
    addTearDown(database.close);
    expect(await repo.load(), isEmpty);
    await Future.wait(records.map(repo.append));
    await repo.append(records.last);
    await database.close();
    final reopenedDatabase = AppDatabase(open: () async => sqlite3.open(path));
    final reopened = ExecutionHistoryRepository(reopenedDatabase);
    addTearDown(reopenedDatabase.close);
    expect(await reopened.load(), [...records, records.last]);
  });

  test('数据库打开失败后可重试，关闭后禁止读写', () async {
    var fails = true;
    final database = AppDatabase(
      open: () async {
        if (fails) throw StateError('open failed');
        return sqlite3.openInMemory();
      },
    );
    final repo = ExecutionHistoryRepository(database);
    addTearDown(database.close);
    await expectLater(repo.append(records.first), throwsStateError);
    fails = false;
    await repo.append(records.first);
    expect(await repo.load(), [records.first]);
    await database.close();
    await database.close();
    await expectLater(repo.load(), throwsStateError);
    await expectLater(repo.append(records.last), throwsStateError);
  });

  for (final execute in [false, true]) {
    test('${execute ? '串行重命名' : '目录操作'}准备记录写入失败时不修改 NAS', () async {
      final db = sqlite3.openInMemory();
      final database = AppDatabase(open: () async => db);
      final repo = ExecutionHistoryRepository(database);
      addTearDown(database.close);
      await repo.load();
      db.execute(
        "CREATE TRIGGER fail_insert BEFORE INSERT ON execution_history BEGIN SELECT RAISE(ABORT, 'disk full'); END",
      );
      final dav = RecordingDav();
      addTearDown(dav.close);
      final container = ProviderContainer(
        overrides: [
          organizerProvider.overrideWith(ReadyOrganizer.new),
          executionHistoryRepositoryProvider.overrideWithValue(repo),
          webDavFactoryProvider.overrideWithValue((_) => dav),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(organizerProvider.notifier);
      if (execute) {
        await controller.execute();
      } else {
        await controller.manage('mkdir', '/dav/new/');
      }
      expect(dav.writes, 0);
      expect(await repo.load(), isEmpty);
      expect(container.read(organizerProvider).hasError, isTrue);
    });
  }

  test('完成记录写入失败时保留准备记录并提示停止核对', () async {
    final db = sqlite3.openInMemory();
    final database = AppDatabase(open: () async => db);
    final repo = ExecutionHistoryRepository(database);
    addTearDown(database.close);
    await repo.load();
    db.execute(
      "CREATE TRIGGER fail_completed BEFORE INSERT ON execution_history WHEN NEW.record LIKE '%完成%' BEGIN SELECT RAISE(ABORT, 'disk full'); END",
    );
    final dav = RecordingDav();
    addTearDown(dav.close);
    final container = ProviderContainer(
      overrides: [
        organizerProvider.overrideWith(ReadyOrganizer.new),
        executionHistoryRepositoryProvider.overrideWithValue(repo),
        webDavFactoryProvider.overrideWithValue((_) => dav),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(organizerProvider.notifier)
        .manage('mkdir', '/dav/new/');
    expect(dav.writes, 1);
    expect((await repo.load()).single, contains('准备 mkdir'));
    expect(container.read(organizerProvider).message, contains('请刷新目录核对结果'));
  });
}
