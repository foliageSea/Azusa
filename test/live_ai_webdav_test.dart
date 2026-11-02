import 'dart:convert';
import 'dart:io';

import 'package:azusa/features/organizer/ai/agent.dart';
import 'package:azusa/features/organizer/connections/connection_settings.dart';
import 'package:azusa/features/organizer/dav/dav_paths.dart';
import 'package:azusa/features/organizer/rename_plan.dart';
import 'package:azusa/features/organizer/ai/tmdb.dart';
import 'package:azusa/features/organizer/dav/webdav.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart' show debugPrint;

void main() {
  final environment = Platform.environment;
  final enabled = [
    'AZU_WEBDAV_URL',
    'AZU_AI_URL',
    'AZU_AI_MODEL',
    'AZU_AI_KEY',
    'AZU_TMDB_KEY',
  ].every((key) => environment[key]?.isNotEmpty == true);
  test(
    '真实 AI + TMDB + Python WebDAV：生成、编辑、排除、串行执行',
    () async {
      final settings = ConnectionSettings(
        webdavUrl: environment['AZU_WEBDAV_URL']!,
        username: 'azu',
        webdavPassword: 'azu-local-test',
        aiUrl: environment['AZU_AI_URL']!,
        model: environment['AZU_AI_MODEL']!,
        aiKey: environment['AZU_AI_KEY']!,
        tmdbToken: environment['AZU_TMDB_KEY']!,
      );
      final dav = WebDavClient(settings);
      final tmdb = TmdbClient(settings);
      final agent = RenameAgent(settings, dav, tmdb);
      addTearDown(() {
        agent.close();
        tmdb.close();
        dav.close();
      });
      final directory = childDavPath(
        dav.root,
        'AI端到端-${DateTime.now().microsecondsSinceEpoch}',
        directory: true,
      );
      await dav.mkdir(directory);
      for (var i = 1; i <= 3; i++) {
        final content = utf8.encode('AZU AI END TO END TEST EPISODE $i');
        await dav.upload(
          childDavPath(directory, 'Breaking.Bad.S01E0$i.1080p.mkv'),
          Stream.value(content),
          content.length,
        );
      }
      final entries = await dav.list(directory);
      final proposal = await agent.propose(
        directory,
        entries,
        instruction: '这三个文件是绝命毒师 Breaking Bad 第1季第1至3集，TMDB series_id=1396。必须调用 TMDB 核对，使用中文剧名和中文集名。不要修改文件扩展名。',
        onStatus: (message) => debugPrint('Agent: $message'),
      );
      expect(proposal.length, 3);
      expect(validatePlan(proposal, entries), isNull);
      final ordered = proposal.toList()
        ..sort((a, b) => a.source.compareTo(b.source));
      for (final item in ordered) {
        expect(item.reason, contains('TMDB 1396'));
        debugPrint(
          '建议: ${Uri.decodeComponent(item.source.split('/').last)} → ${item.targetName}',
        );
      }
      final modifiedName =
          '${ordered.first.targetName.substring(0, ordered.first.targetName.length - 4)} - 手动确认.mkv';
      final plan = [
        ordered[0].copyWith(targetName: modifiedName),
        ordered[1],
        ordered[2].copyWith(enabled: false),
      ];
      expect(validatePlan(plan, entries), isNull);
      final progress = <int>[];
      final result = await RenameExecutor(dav)
          .execute(plan, onProgress: (done, total) => progress.add(done));
      expect(result.error, isNull);
      expect(result.completed.length, 2);
      expect(progress, [1, 2]);
      expect(await dav.exists(plan[0].target), isTrue);
      expect(await dav.exists(plan[1].target), isTrue);
      expect(await dav.exists(ordered[2].source), isTrue);
      expect(await dav.exists(ordered[2].target), isFalse);
      final finalEntries = await dav.list(directory);
      expect(finalEntries.length, 3);
      debugPrint('测试目录: ${displayDavPath(directory)}');
      for (final entry in finalEntries) {
        debugPrint('最终文件: ${entry.name}');
      }
    },
    skip: enabled ? false : '需要配置 AZU_WEBDAV_URL / AZU_AI_* / AZU_TMDB_KEY',
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
