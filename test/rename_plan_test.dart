import 'package:flutter_test/flutter_test.dart';
import 'package:azusa/features/organizer/connections/connection_settings.dart';
import 'package:azusa/features/organizer/dav/dav_paths.dart';
import 'package:azusa/features/organizer/rename_plan.dart';
import 'package:azusa/features/organizer/dav/webdav.dart';

class MemoryDav extends WebDavClient {
  MemoryDav(this.files)
    : super(const ConnectionSettings(webdavUrl: 'https://nas.test/dav/'));
  final Map<String, DavEntry> files;
  final List<String> moved = [];
  int active = 0, maximum = 0;
  String? fail;
  @override
  Future<List<DavEntry>> list(String path) async => files.values.toList();
  @override
  Future<DavEntry?> stat(String path) async => files[path];
  @override
  Future<void> move(String from, String to, {String? etag}) async {
    active++;
    if (active > maximum) maximum = active;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 2));
      if (fail == from) throw StateError('模拟失败');
      files[to] = DavEntry(to, false);
      files.remove(from);
      moved.add(from);
    } finally {
      active--;
    }
  }
}

void main() {
  const entries = [
    DavEntry('/dav/a.mkv', false),
    DavEntry('/dav/b.mkv', false),
  ];
  const first = RenameItem(source: '/dav/a.mkv', targetName: '剧集 - S01E01.mkv');
  const second = RenameItem(
    source: '/dav/b.mkv',
    targetName: '剧集 - S01E02.mkv',
  );

  test('中文、空格、百分号不会重复编码', () {
    final path = childDavPath('/dav/', '剧集 100%.mkv');
    expect(displayDavPath(path), '/dav/剧集 100%.mkv');
    expect(canonicalDavPath(path), path);
    final dav = MemoryDav({});
    addTearDown(dav.close);
    expect(dav.url(path).toString(), 'https://nas.test$path');
  });

  test('拒绝路径越界和编码后的分隔符', () {
    final dav = MemoryDav({});
    addTearDown(dav.close);
    for (final path in [
      '/other/a.mkv',
      '/dav/../a',
      '/dav/%2e%2e/a',
      '/dav/a%2fb',
    ]) {
      expect(() => dav.url(path), throwsFormatException);
    }
  });

  test('合法计划可执行，扩展名不能改变', () {
    expect(validatePlan([first, second], entries), isNull);
    expect(
      validatePlan([first.copyWith(targetName: 'a.mp4')], entries),
      contains('扩展名'),
    );
  });

  test('建议名称将非法字符替换为全角字符', () {
    final name = sanitizeSuggestedFileName(
      '22 / 7 - S01E12 - 22/7.mp4',
      originalName: '22／7 - S01E12.mp4',
    );
    expect(name, '22 ／ 7 - S01E12 - 22／7.mp4');
    expect(validFileName(name), isTrue);
    expect(
      sanitizeSuggestedFileName(
        'a/b\\c:d*e?f"g<h>i|j\u0000\n\u007f.mkv. ',
        originalName: 'original.mkv',
      ),
      'a／b＼c：d＊e？f＂g＜h＞i｜j.mkv',
    );
  });

  test('建议名称保留原扩展名、字幕语言和合法字符', () {
    expect(
      sanitizeSuggestedFileName('剧集 100%.zh.ass', originalName: 'a.zh.ass'),
      '剧集 100%.zh.ass',
    );
    expect(
      sanitizeSuggestedFileName('剧集.mp4', originalName: 'a.MKV'),
      '剧集.MKV',
    );
    expect(sanitizeSuggestedFileName('剧集', originalName: 'a.mkv'), '剧集.mkv');
    for (final name in ['', ' ', '.', '..', '\u0000']) {
      expect(sanitizeSuggestedFileName(name, originalName: 'a.mkv'), 'a.mkv');
    }
    expect(sanitizeSuggestedFileName('剧集. ', originalName: 'a'), '剧集');
  });

  test('手动输入非法名称时提示具体字符及替代方式', () {
    expect(
      validatePlan([first.copyWith(targetName: '22/7.mkv')], entries),
      '文件名无效：不能包含“/”，请替换为“／”或“-”',
    );
    expect(fileNameError('a.mkv\n'), contains('控制字符'));
    expect(fileNameError('a.mkv '), contains('结尾'));
    expect(fileNameError('22／7.mkv'), isNull);
  });

  test('自动替换后的重复名称和已有目标仍被拒绝', () async {
    final plan = [
      first.copyWith(
        targetName: sanitizeSuggestedFileName(
          '22/7.mkv',
          originalName: 'a.mkv',
        ),
      ),
      second.copyWith(
        targetName: sanitizeSuggestedFileName(
          '22／7.mkv',
          originalName: 'b.mkv',
        ),
      ),
    ];
    expect(validatePlan(plan, entries), contains('重复'));
    final dav = MemoryDav({for (final e in entries) e.path: e});
    addTearDown(dav.close);
    expect((await RenameExecutor(dav).execute(plan)).error, contains('重复'));
    expect(dav.moved, isEmpty);
    final existing = [...entries, DavEntry(plan.first.target, false)];
    expect(validatePlan([plan.first], existing), contains('已存在'));
  });

  test('拒绝重复源、重复目标、已有目标和非法文件名', () {
    expect(validatePlan([first, first], entries), contains('源文件'));
    expect(
      validatePlan([
        first,
        second.copyWith(targetName: first.targetName),
      ], entries),
      contains('重复'),
    );
    expect(
      validatePlan([first.copyWith(targetName: 'b.mkv')], entries),
      contains('已存在'),
    );
    for (final name in ['../a.mkv', 'bad\\a.mkv', 'bad?.mkv', '']) {
      expect(
        validatePlan([first.copyWith(targetName: name)], entries),
        contains('无效'),
      );
    }
  });

  test('取消勾选的项不参与校验', () {
    expect(
      validatePlan([first.copyWith(targetName: '', enabled: false)], entries),
      isNull,
    );
  });

  test('目录不能作为视频文件执行', () {
    expect(
      validatePlan([first], [const DavEntry('/dav/a.mkv', true)]),
      isNotNull,
    );
  });

  test('串行执行且每项成功后记录', () async {
    final dav = MemoryDav({for (final e in entries) e.path: e});
    addTearDown(dav.close);
    final records = <String>[];
    final result = await RenameExecutor(dav).execute(
      [first, second],
      onCompleted: (item) async {
        records.add(item.source);
      },
    );
    expect(result.error, isNull);
    expect(result.completed, [first, second]);
    expect(dav.maximum, 1);
    expect(records, ['/dav/a.mkv', '/dav/b.mkv']);
  });

  test('失败立即停止，已成功项不重复执行，剩余项可继续', () async {
    final dav = MemoryDav({for (final e in entries) e.path: e})
      ..fail = second.source;
    addTearDown(dav.close);
    final executor = RenameExecutor(dav);
    final failed = await executor.execute([first, second]);
    expect(failed.completed, [first]);
    expect(failed.error, contains('模拟失败'));
    dav.fail = null;
    final resumed = await executor.execute([second]);
    expect(resumed.error, isNull);
    expect(dav.moved, [first.source, second.source]);
  });

  test('预览后源文件发生变化时不修改', () async {
    final dav = MemoryDav({
      '/dav/a.mkv': const DavEntry('/dav/a.mkv', false, etag: 'new'),
    });
    addTearDown(dav.close);
    final item = RenameItem(
      source: first.source,
      targetName: first.targetName,
      fingerprint: 'old',
    );
    final result = await RenameExecutor(dav).execute([item]);
    expect(result.error, contains('已变化'));
    expect(dav.moved, isEmpty);
  });

  test('写入准备日志失败时不执行 NAS 修改', () async {
    final dav = MemoryDav({for (final e in entries) e.path: e});
    addTearDown(dav.close);
    final result = await RenameExecutor(dav)
        .execute([first], onStarting: (_) async => throw StateError('存储失败'));
    expect(result.error, contains('存储失败'));
    expect(dav.moved, isEmpty);
  });
}
