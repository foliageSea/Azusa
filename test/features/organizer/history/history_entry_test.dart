import 'package:azusa/features/organizer/history/history_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HistoryEntry path changes', () {
    test('identifies a rename within the same directory', () {
      final entry = HistoryEntry.parse(
        '完成重命名 /dav/Season 01/old.mkv → /dav/Season 01/new.mkv',
      );

      expect(entry.pathChange, HistoryPathChange.rename);
      expect(entry.title, '重命名');
      expect(entry.sourceSummary, 'old.mkv');
      expect(entry.targetSummary, 'new.mkv');
    });

    test('identifies a move without a filename change', () {
      final entry = HistoryEntry.parse(
        '完成重命名 /dav/old/episode.mkv → /dav/new/episode.mkv',
      );

      expect(entry.pathChange, HistoryPathChange.move);
      expect(entry.title, '移动');
      expect(entry.sourceSummary, 'episode.mkv');
      expect(entry.targetSummary, 'episode.mkv');
    });

    test('identifies moving and renaming from legacy rename records', () {
      const source =
          '/dav/批量整理测试/绝命毒师/Season 01/发布组 100%/Breaking.Bad.S01E01.1080p.mkv';
      const target = '/dav/批量整理测试/绝命毒师 (2008)/Season 01/绝命毒师 - S01E01 - 向导.mkv';
      final entry = HistoryEntry.parse('完成重命名 $source → $target');

      expect(entry.pathChange, HistoryPathChange.moveAndRename);
      expect(entry.title, '移动并重命名');
      expect(entry.sourceSummary, 'Breaking.Bad.S01E01.1080p.mkv');
      expect(entry.targetSummary, '绝命毒师 - S01E01 - 向导.mkv');
    });

    test('parses source and target in move records too', () {
      final entry = HistoryEntry.parse(
        '完成 move /dav/old/episode.mkv → /dav/new/renamed.mkv',
      );

      expect(entry.action, 'move');
      expect(entry.source, '/dav/old/episode.mkv');
      expect(entry.target, '/dav/new/renamed.mkv');
      expect(entry.pathChange, HistoryPathChange.moveAndRename);
    });

    test('handles root paths and trailing directory slashes', () {
      final moved = HistoryEntry.parse('完成重命名 /old/ → /parent/old/');
      final renamed = HistoryEntry.parse('完成重命名 /old/ → /new/');

      expect(moved.pathChange, HistoryPathChange.move);
      expect(renamed.pathChange, HistoryPathChange.rename);
      expect(renamed.sourceSummary, 'old');
      expect(renamed.targetSummary, 'new');
    });

    test('keeps records without usable path pairs unchanged', () {
      final entry = HistoryEntry.parse('完成 move legacy payload');
      final upload = HistoryEntry.parse('完成 upload /dav/episode.mkv');
      final unchanged = HistoryEntry.parse(
        '完成重命名 /dav/episode.mkv → /dav/episode.mkv',
      );

      expect(entry.pathChange, isNull);
      expect(entry.title, '移动 / 重命名');
      expect(entry.sourceSummary, isNull);
      expect(upload.pathChange, isNull);
      expect(upload.title, '上传文件');
      expect(upload.sourceSummary, 'episode.mkv');
      expect(unchanged.pathChange, isNull);
    });

    test('preserves start/completion pairing for moved and renamed files', () {
      final entries = HistoryEntry.fromRecords([
        '2026-11-05 09:14:20 准备重命名 /dav/old/a.mkv → /dav/new/b.mkv',
        '2026-11-05 09:14:21 完成重命名 /dav/old/a.mkv → /dav/new/b.mkv',
      ]);

      expect(entries, hasLength(1));
      expect(entries.single.completed, isTrue);
      expect(entries.single.startedAt, DateTime(2026, 11, 5, 9, 14, 20));
      expect(entries.single.time, DateTime(2026, 11, 5, 9, 14, 21));
      expect(entries.single.pathChange, HistoryPathChange.moveAndRename);
      expect(entries.single.sourceSummary, 'a.mkv');
      expect(entries.single.targetSummary, 'b.mkv');
    });
  });
}
