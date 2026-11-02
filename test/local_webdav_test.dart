import 'dart:convert';
import 'dart:io';

import 'package:azusa/features/organizer/connections/connection_settings.dart';
import 'package:azusa/features/organizer/dav/dav_paths.dart';
import 'package:azusa/features/organizer/rename_plan.dart';
import 'package:azusa/features/organizer/dav/webdav.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

final localUrl = Platform.environment['AZU_WEBDAV_URL'];

void main() {
  group(
    'Python WebDAV 真实协议联调',
    skip: localUrl == null ? '设置 AZU_WEBDAV_URL 后运行' : false,
    () {
      late WebDavClient dav;
      late String directory;
      setUpAll(() async {
        dav = WebDavClient(
          ConnectionSettings(
            webdavUrl: localUrl!,
            username: 'azu',
            webdavPassword: 'azu-local-test',
          ),
        );
        final root = await dav.list(dav.root);
        expect(root.map((e) => e.name), contains('剧集测试'));
        directory = childDavPath(
          dav.root,
          '联调-${DateTime.now().microsecondsSinceEpoch}',
          directory: true,
        );
        await dav.mkdir(directory);
      });
      tearDownAll(() => dav.close());

      Future<String> put(String name, String content) async {
        final path = childDavPath(directory, name);
        final bytes = utf8.encode(content);
        await dav.upload(path, Stream.value(bytes), bytes.length);
        return path;
      }

      RenameItem rename(DavEntry entry, String name) => RenameItem(
        source: entry.path,
        targetName: name,
        fingerprint: entry.fingerprint,
        etag: entry.etag,
        reason: '本地真实 WebDAV 测试',
      );

      test('基础认证拒绝错误密码', () async {
        final denied = WebDavClient(
          ConnectionSettings(
            webdavUrl: localUrl!,
            username: 'azu',
            webdavPassword: 'wrong',
          ),
        );
        addTearDown(denied.close);
        await expectLater(
          denied.list(denied.root),
          throwsA(
            isA<DioException>().having(
              (e) => e.response?.statusCode,
              'status',
              401,
            ),
          ),
        );
      });

      test('读取独立中文目录与百分号文件', () async {
        var path = directory;
        for (final name in ['剧集测试', '绝命毒师', 'Season 01']) {
          path = childDavPath(path, name, directory: true);
          await dav.mkdir(path);
        }
        for (final name in ['说明 100%.txt', 'Breaking.Bad.S01E01.1080p.mkv']) {
          final content = utf8.encode('isolated fixture');
          await dav.upload(
            childDavPath(path, name),
            Stream.value(content),
            content.length,
          );
        }
        final entries = await dav.list(path);
        expect(
          entries.map((e) => e.name),
          containsAll(['说明 100%.txt', 'Breaking.Bad.S01E01.1080p.mkv']),
        );
        expect(entries.length, 2);
      });

      test('创建、流式上传、下载逐字节一致、移动与删除', () async {
        final from = await put('中文 100% & [test].txt', '中文测试\n123\n');
        final entry = await dav.stat(from);
        expect(entry?.name, '中文 100% & [test].txt');
        expect(entry?.size, utf8.encode('中文测试\n123\n').length);
        final local = await Directory('/tmp/opencode')
            .createTemp('azu-download-');
        try {
          final output = '${local.path}/download.txt';
          await dav.download(from, output);
          expect(await File(output).readAsBytes(), utf8.encode('中文测试\n123\n'));
        } finally {
          await local.delete(recursive: true);
        }
        final to = childDavPath(directory, '移动后的文件 100%.txt');
        await dav.move(from, to, etag: entry!.etag);
        expect(await dav.exists(from), isFalse);
        expect(await dav.exists(to), isTrue);
        await dav.remove(to);
        expect(await dav.exists(to), isFalse);
      });

      test('同名上传和 MOVE 均不覆盖已有文件', () async {
        final source = await put('source.txt', 'source');
        final target = await put('protected.txt', 'protected');
        await expectLater(
          dav.move(source, target),
          throwsA(
            isA<DioException>().having(
              (e) => e.response?.statusCode,
              'status',
              412,
            ),
          ),
        );
        await expectLater(
          dav.upload(target, Stream.value([1, 2]), 2),
          throwsA(
            isA<DioException>().having(
              (e) => e.response?.statusCode,
              'status',
              412,
            ),
          ),
        );
        expect(await dav.exists(source), isTrue);
        expect((await dav.stat(target))?.size, 'protected'.length);
      });

      test('真实 ETag 过期时 MOVE 拒绝修改', () async {
        final source = await put('etag.txt', 'unchanged');
        final target = childDavPath(directory, 'etag-renamed.txt');
        await expectLater(
          dav.move(source, target, etag: '"stale-etag"'),
          throwsA(
            isA<DioException>().having(
              (e) => e.response?.statusCode,
              'status',
              412,
            ),
          ),
        );
        expect(await dav.exists(source), isTrue);
        expect(await dav.exists(target), isFalse);
      });

      test('真实 MOVE 串行整理且人工改名生效', () async {
        final plan = <RenameItem>[];
        for (var i = 1; i <= 3; i++) {
          final source = await put('serial.S01E0$i.mkv', 'episode-$i');
          plan.add(
            rename((await dav.stat(source))!, '人工修改 - S01E0$i - 测试集.mkv'),
          );
        }
        final events = <String>[];
        final result = await RenameExecutor(dav).execute(
          plan,
          onStarting: (item) async {
            events.add('start:${item.source}');
          },
          onCompleted: (item) async {
            events.add('done:${item.source}');
          },
        );
        expect(result.error, isNull);
        expect(result.completed.length, 3);
        for (var i = 0; i < plan.length; i++) {
          expect(events[i * 2], 'start:${plan[i].source}');
          expect(events[i * 2 + 1], 'done:${plan[i].source}');
          expect(await dav.exists(plan[i].target), isTrue);
          expect(await dav.exists(plan[i].source), isFalse);
        }
      });

      test('第二项发生目标竞争则停止，第三项不执行，排除冲突后续作', () async {
        final plan = <RenameItem>[];
        for (var i = 1; i <= 3; i++) {
          final source = await put('failure.S01E0$i.mkv', 'failure-$i');
          plan.add(rename((await dav.stat(source))!, '失败续作 - S01E0$i.mkv'));
        }
        final executor = RenameExecutor(dav);
        final failed = await executor.execute(
          plan,
          onStarting: (item) async {
            if (item.source == plan[1].source) {
              await dav.upload(
                item.target,
                Stream.value(utf8.encode('race-created')),
                'race-created'.length,
              );
            }
          },
        );
        expect(failed.completed, [plan.first]);
        expect(failed.error, isNotNull);
        expect(await dav.exists(plan[0].target), isTrue);
        expect(await dav.exists(plan[1].source), isTrue);
        expect(await dav.exists(plan[2].source), isTrue);
        expect(await dav.exists(plan[2].target), isFalse);
        await dav.remove(plan[1].target);
        final resumed = await executor.execute(plan.skip(1).toList());
        expect(resumed.error, isNull);
        expect(resumed.completed.length, 2);
        for (final item in plan) {
          expect(await dav.exists(item.target), isTrue);
        }
      });

      test('目录可移动并删除，连接根目录外的路径被拒绝', () async {
        final child = childDavPath(directory, '子目录', directory: true);
        final moved = childDavPath(directory, '移动后的子目录', directory: true);
        await dav.mkdir(child);
        await dav.move(child, moved);
        expect(await dav.exists(moved), isTrue);
        await dav.remove(moved);
        expect(await dav.exists(moved), isFalse);
        expect(() => dav.url('/outside'), throwsFormatException);
      });
    },
  );
}
