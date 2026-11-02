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

class RenameDav extends RecordingDav {
  RenameDav(this.files);

  final Map<String, DavEntry> files;
  final moves = <(String, String)>[];

  @override
  Future<DavEntry?> stat(String path) => Future.value(files[path]);

  @override
  Future<List<DavEntry>> list(String path) async => files.values.toList();

  @override
  Future<void> move(String from, String to, {String? etag}) async {
    moves.add((from, to));
    final entry = files.remove(from)!;
    files[to] = DavEntry(to, entry.directory);
  }
}

class RenameOrganizer extends ReadyOrganizer {
  @override
  OrganizerState build() => const OrganizerState(
    directory: '/dav/',
    entries: [
      DavEntry('/dav/a.mkv', false),
      DavEntry('/dav/season/', true),
      DavEntry('/dav/taken.mkv', false),
    ],
  );
}

void main() {
  test('目录文件和文件夹重命名保留类型且冲突时不写入 NAS', () async {
    final database = AppDatabase(open: () async => sqlite3.openInMemory());
    addTearDown(database.close);
    final repo = ExecutionHistoryRepository(database);
    final dav = RenameDav({
      '/dav/a.mkv': const DavEntry('/dav/a.mkv', false),
      '/dav/season/': const DavEntry('/dav/season/', true),
      '/dav/taken.mkv': const DavEntry('/dav/taken.mkv', false),
    });
    addTearDown(dav.close);
    final container = ProviderContainer(
      overrides: [
        organizerProvider.overrideWith(RenameOrganizer.new),
        executionHistoryRepositoryProvider.overrideWithValue(repo),
        webDavFactoryProvider.overrideWithValue((_) => dav),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(organizerProvider.notifier);

    await controller.renameEntry(
      const DavEntry('/dav/a.mkv', false),
      '新 剧集%.mkv',
    );
    await controller.renameEntry(const DavEntry('/dav/season/', true), '第二季');
    expect(dav.moves, [
      ('/dav/a.mkv', '/dav/%E6%96%B0%20%E5%89%A7%E9%9B%86%25.mkv'),
      ('/dav/season/', '/dav/%E7%AC%AC%E4%BA%8C%E5%AD%A3/'),
    ]);
    expect(
      container
          .read(organizerProvider)
          .entries
          .any(
            (e) => e.path == '/dav/%E7%AC%AC%E4%BA%8C%E5%AD%A3/' && e.directory,
          ),
      isTrue,
    );
    await controller.renameEntry(
      const DavEntry('/dav/taken.mkv', false),
      '新 剧集%.mkv',
    );
    expect(container.read(organizerProvider).message, contains('已存在'));
    await controller.renameEntry(
      const DavEntry('/dav/taken.mkv', false),
      'bad/name',
    );
    expect(container.read(organizerProvider).message, contains('无效'));
    expect(dav.moves.length, 2);
    expect((await repo.load()).length, 4);
  });

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
