import 'package:azusa/features/organizer/history/history_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('保留时间戳的时区以便正确转换为本地时间', () {
    final entry = HistoryEntry.parse(
      '2026-11-02 20:49:56.117603+08:00 完成重命名 /a → /b',
    );
    expect(entry.time, DateTime.utc(2026, 11, 2, 12, 49, 56, 117, 603));
  });
  test('解析日期、重命名路径并合并准备和完成记录', () {
    final entries = HistoryEntry.fromRecords([
      '2026-11-02 09:48:54.720825 准备重命名 /dav/剧集/a.mkv → /dav/剧集/新名称.mkv',
      '2026-11-02 09:48:54.738497 完成重命名 /dav/剧集/a.mkv → /dav/剧集/新名称.mkv',
    ]);
    expect(entries, hasLength(1));
    expect(entries.single.completed, isTrue);
    expect(entries.single.source, '/dav/剧集/a.mkv');
    expect(entries.single.target, '/dav/剧集/新名称.mkv');
    expect(entries.single.time, DateTime(2026, 11, 2, 9, 48, 54, 738, 497));
    expect(
      entries.single.startedAt,
      DateTime(2026, 11, 2, 9, 48, 54, 720, 825),
    );
  });

  test('保留未完成操作且按倒序显示，不误报失败', () {
    final entries = HistoryEntry.fromRecords([
      '2026-11-02 09:48:54.720825 准备 delete /dav/旧文件.txt ',
      '2026-11-02 09:48:55.720825 准备 mkdir /dav/新目录/ ',
    ]);
    expect(entries, hasLength(2));
    expect(entries.first.title, '新建文件夹');
    expect(entries.first.completed, isFalse);
    expect(entries.last.source, '/dav/旧文件.txt');
  });

  test('相同路径的操作只在同一连接内配对，连接改名不影响配对', () {
    const a = HistoryServer(connectionId: 'a', name: '旧名称', protocol: 'smb');
    const renamed = HistoryServer(
      connectionId: 'a',
      name: '新名称',
      protocol: 'smb',
    );
    const b = HistoryServer(connectionId: 'b', name: '另一台', protocol: 'smb');
    const c = HistoryServer(connectionId: 'c', name: 'DAV', protocol: 'webdav');
    const start = '2026-11-02 10:00:00 准备 delete /same.mkv ';
    const done = '2026-11-02 10:01:00 完成 delete /same.mkv ';
    final entries = HistoryEntry.fromStoredRecords(const [
      ExecutionHistoryRecord(start, server: a),
      ExecutionHistoryRecord(start, server: b),
      ExecutionHistoryRecord(start, server: c),
      ExecutionHistoryRecord(start),
      ExecutionHistoryRecord(done, server: renamed),
    ]);
    expect(entries, hasLength(4));
    expect(entries.first.completed, isTrue);
    expect(entries.first.startedAt, DateTime(2026, 11, 2, 10));
    expect(entries.first.server?.name, '新名称');
    expect(entries.skip(1).map((entry) => entry.server?.connectionId), [
      null,
      'c',
      'b',
    ]);
    expect(entries.skip(1).every((entry) => entry.completed == false), isTrue);
  });

  test('重复操作只合并对应的一组', () {
    final entries = HistoryEntry.fromRecords([
      '准备 upload /dav/a.txt ',
      '完成 upload /dav/a.txt ',
      '准备 upload /dav/a.txt ',
    ]);
    expect(entries, hasLength(2));
    expect(entries.first.completed, isFalse);
    expect(entries.last.completed, isTrue);
  });

  test('兼容无时间或无法解析的旧记录和含空格的路径', () {
    final entries = HistoryEntry.fromRecords([
      '旧记录内容',
      '完成重命名 /dav/Season 01/a 100%.mkv → /dav/Season 01/b.mkv',
      '完成 move /dav/旧目录/a.mkv /dav/新目录/a.mkv',
    ]);
    expect(entries[0].title, '移动 / 重命名');
    expect(entries[0].source, isNull);
    expect(entries[0].message, contains('/dav/旧目录/a.mkv'));
    expect(entries[1].source, '/dav/Season 01/a 100%.mkv');
    expect(entries[2].message, '旧记录内容');
    expect(entries[2].completed, isNull);
  });
}
