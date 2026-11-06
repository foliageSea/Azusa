import 'package:azusa/features/organizer/ai/agent.dart';
import 'package:azusa/features/organizer/dav/webdav.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('字幕按作品和季集匹配带发布信息的视频，保留原有精确匹配', () {
    for (final video in [
      'Breaking.Bad.S01E01.1080p.mkv',
      'breaking_bad_s1e1_1080p_BluRay.mkv',
      'Breaking Bad S01E01 - Pilot.mkv',
    ]) {
      for (final subtitle in [
        'Breaking.Bad.S01E01.zh.srt',
        'Breaking.Bad.S01E01.zh-Hans.forced.ass',
        'Breaking.Bad.S01E01.srt',
      ]) {
        expect(
          subtitleMatchesVideo(subtitle, video),
          isTrue,
          reason: '$subtitle → $video',
        );
      }
    }
    expect(subtitleMatchesVideo('movie.zh-Hans.srt', 'movie.mkv'), isTrue);
    expect(subtitleMatchesVideo('raw.zh.srt', 'raw.mkv'), isTrue);
  });

  test('不同作品、季集及直接连写的多集视频不误配', () {
    for (final video in [
      'Better.Call.Saul.S01E01.1080p.mkv',
      'Breaking.Bad.S02E01.1080p.mkv',
      'Breaking.Bad.S01E02.1080p.mkv',
      'Breaking.Bad.S01E010.1080p.mkv',
      'Breaking.Bad.S01E01E02.1080p.mkv',
      'unrelated.mkv',
    ]) {
      expect(
        subtitleMatchesVideo('Breaking.Bad.S01E01.zh.srt', video),
        isFalse,
        reason: video,
      );
    }
  });

  test('漏配字幕进入对应视频批次，普通文件和其他目录字幕不混入', () {
    const video = DavEntry(
      '/dav/Season%2001/Breaking.Bad.S01E01.1080p.mkv',
      false,
    );
    const subtitle = DavEntry(
      '/dav/Season%2001/Breaking.Bad.S01E01.zh.srt',
      false,
    );
    final batches = RenameAgent.batches('/dav/', [
      video,
      subtitle,
      const DavEntry('/dav/Season%2001/%E8%AF%B4%E6%98%8E.txt', false),
      const DavEntry('/dav/other/Breaking.Bad.S01E01.zh.srt', false),
    ]);
    expect(batches.single, [video, subtitle]);
  });

  test('同集多个视频版本有歧义时字幕不进入任何批次', () {
    final batches = RenameAgent.batches('/dav/', const [
      DavEntry('/dav/Breaking.Bad.S01E01.1080p.mkv', false),
      DavEntry('/dav/Breaking.Bad.S01E01.2160p.mkv', false),
      DavEntry('/dav/Breaking.Bad.S01E01.zh.srt', false),
    ]);
    expect(batches.single, hasLength(2));
    expect(batches.single.every(RenameAgent.isVideo), isTrue);
  });
}
