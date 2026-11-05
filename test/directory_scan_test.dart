import 'package:azusa/features/organizer/ai/agent.dart';
import 'package:azusa/core/database/app_database.dart';
import 'package:azusa/features/organizer/ai/agent_activity.dart';
import 'package:azusa/features/organizer/ai/ai_usage.dart';
import 'package:azusa/features/organizer/ai/ai_usage_history.dart';
import 'package:azusa/features/organizer/ai/folder_layout.dart';
import 'package:azusa/features/organizer/organizer_state.dart';
import 'package:azusa/features/organizer/rename_plan.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:azusa/features/organizer/connections/connection_settings.dart';
import 'package:azusa/features/organizer/dav/directory_scan.dart';
import 'package:azusa/features/organizer/dav/webdav.dart';
import 'package:flutter_test/flutter_test.dart';

class _Dav extends WebDavClient {
  _Dav(List<DavEntry> entries)
    : files = {for (final e in entries) e.path: e},
      super(const ConnectionSettings(webdavUrl: 'https://nas.test/dav/'));
  final Map<String, DavEntry> files;
  final deleted = <String>[];
  String? fail;
  @override
  Future<List<DavEntry>> listAll(String path) async {
    if (path == fail) throw StateError('permission denied');
    return files.values
        .where(
          (e) =>
              e.path != path &&
              e.path.startsWith(path) &&
              !e.path
                  .substring(path.length)
                  .replaceFirst(RegExp(r'/$'), '')
                  .contains('/'),
        )
        .toList();
  }

  @override
  Future<List<DavEntry>> list(String path) => listAll(path);
  @override
  Future<void> remove(String path) async {
    if (path == fail) throw StateError('permission denied');
    expect(await listAll(path), isEmpty);
    deleted.add(path);
    files.remove(path);
  }
}

class _Connections extends ConnectionSettingsController {
  @override
  Future<ConnectionSettings> build() async => const ConnectionSettings(
    webdavUrl: 'https://nas.test/dav/',
    model: 'test',
  );
}

class _Agent extends RenameAgent {
  _Agent(super.settings, super.dav, super.tmdb);
  bool closed = false;
  @override
  Future<List<RenameItem>> propose(
    String directory,
    List<DavEntry> entries, {
    String instruction = '',
    FolderLayout? folderLayout,
    void Function(String)? onStatus,
    void Function(AiUsage)? onUsage,
    void Function(AgentActivity)? onActivity,
    void Function(FolderLayout)? onLayout,
  }) async {
    expect(closed, isFalse);
    onUsage?.call(
      const AiUsage(inputTokens: 10, outputTokens: 5, responses: 1),
    );
    onActivity?.call(
      const AgentActivity(key: 'model-1', kind: AgentActivityKind.model),
    );
    return [
      for (final entry in entries.where(RenameAgent.isVideo))
        RenameItem(
          source: entry.path,
          targetName: entry.name,
          scope: directory,
          tmdbMediaType: TmdbMediaType.tv,
          tmdbId: 1,
          mediaTitle: 'Show',
          seasonNumber: 1,
        ),
    ];
  }

  @override
  void close() {
    closed = true;
    super.close();
  }
}

void main() {
  test(
    'delete failure and cancellation stop later folders without rollback',
    () async {
      final dav = _Dav([
        const DavEntry('/dav/a/', true),
        const DavEntry('/dav/b/', true),
        const DavEntry('/dav/c/', true),
      ]);
      addTearDown(dav.close);
      final cleaner = EmptyDirectoryCleaner(dav);
      dav.fail = '/dav/b/';
      await expectLater(
        cleaner.clean('/dav/', ['/dav/a/', '/dav/b/', '/dav/c/']),
        throwsStateError,
      );
      expect(dav.deleted, ['/dav/a/']);
      dav.fail = null;
      var cancelled = false;
      await expectLater(
        cleaner.clean(
          '/dav/',
          ['/dav/b/', '/dav/c/'],
          checkCancelled: () {
            if (cancelled) throw StateError('stop');
          },
          onDeleted: (_) async {
            cancelled = true;
          },
        ),
        throwsStateError,
      );
      expect(dav.deleted, ['/dav/a/', '/dav/b/']);
      expect(dav.files.containsKey('/dav/c/'), isTrue);
    },
  );
  test('controller creates separate agents, aggregates usage and merges plans under selected root', () async {
    final db = AppDatabase(open: () async => sqlite3.openInMemory());
    addTearDown(db.close);
    final dav = _Dav([
      const DavEntry('/dav/show/', true),
      const DavEntry('/dav/show/season/', true),
      for (var i = 0; i < 205; i++)
        DavEntry('/dav/show/season/ep$i.mkv', false),
    ]);
    final agents = <_Agent>[];
    final container = ProviderContainer(
      overrides: [
        connectionSettingsProvider.overrideWith(_Connections.new),
        webDavFactoryProvider.overrideWithValue((_) => dav),
        modelPricingLookupProvider.overrideWithValue((_) async => null),
        aiUsageRepositoryProvider.overrideWithValue(AiUsageRepository(db)),
        renameAgentFactoryProvider.overrideWithValue((settings, dav, tmdb) {
          final agent = _Agent(settings, dav, tmdb);
          agents.add(agent);
          return agent;
        }),
      ],
    );
    addTearDown(container.dispose);
    await container.read(connectionSettingsProvider.future);
    final controller = container.read(organizerProvider.notifier);
    await controller.open('/dav/');
    final keys = <String>[];
    await controller.propose(
      folderLayout: FolderLayout.full,
      onActivity: (a) => keys.add(a.key),
    );
    final result = container.read(organizerProvider);
    expect(result.message, '建议已生成');
    expect(result.plan.length, 205);
    expect(
      result.plan.every((e) => e.targetDirectory == '/dav/Show/Season%2001/'),
      isTrue,
    );
    expect(result.aiUsage!.inputTokens, 30);
    expect(result.aiUsage!.responses, 3);
    expect(agents.length, 3);
    expect(agents.every((a) => a.closed), isTrue);
    expect(keys.where((k) => k.endsWith('model-1')).toSet().length, 3);
  });
  test(
    'recursive scan finds multi-season nested media; disabled scans root only',
    () async {
      final dav = _Dav([
        const DavEntry('/dav/show/', true),
        const DavEntry('/dav/show/season/', true),
        const DavEntry('/dav/show/season/ep.mkv', false),
      ]);
      addTearDown(dav.close);
      expect(
        (await scanMediaDirectories(dav, '/dav/', recursive: true)).length,
        3,
      );
      expect(
        (await scanMediaDirectories(dav, '/dav/', recursive: false)).length,
        1,
      );
    },
  );

  test(
    'empty tree is deleted bottom-up; hidden files and root are preserved',
    () async {
      final dav = _Dav([
        const DavEntry('/dav/a/', true),
        const DavEntry('/dav/a/b/', true),
        const DavEntry('/dav/hidden/', true),
        const DavEntry('/dav/hidden/.keep', false),
        const DavEntry('/dav/.system/', true),
      ]);
      addTearDown(dav.close);
      final cleaner = EmptyDirectoryCleaner(dav);
      final paths = await cleaner.scan('/dav/');
      expect(paths, ['/dav/a/b/', '/dav/a/']);
      final result = await cleaner.clean('/dav/', paths.reversed);
      expect(result.deleted, 2);
      expect(dav.deleted, ['/dav/a/b/', '/dav/a/']);
      expect(dav.files.containsKey('/dav/hidden/.keep'), isTrue);
    },
  );

  test('new contents and unchecked children prevent parent deletion', () async {
    final dav = _Dav([
      const DavEntry('/dav/a/', true),
      const DavEntry('/dav/a/b/', true),
    ]);
    addTearDown(dav.close);
    final cleaner = EmptyDirectoryCleaner(dav);
    await cleaner.scan('/dav/');
    expect((await cleaner.clean('/dav/', ['/dav/a/'])).skipped, 1);
    dav.files['/dav/a/b/new.mkv'] = const DavEntry('/dav/a/b/new.mkv', false);
    expect((await cleaner.clean('/dav/', ['/dav/a/b/', '/dav/a/'])).skipped, 2);
    expect(dav.deleted, isEmpty);
  });

  test(
    'read failure, cancellation and root/out-of-scope cleanup are rejected',
    () async {
      final dav = _Dav([const DavEntry('/dav/a/', true)])..fail = '/dav/a/';
      addTearDown(dav.close);
      final cleaner = EmptyDirectoryCleaner(dav);
      await expectLater(cleaner.scan('/dav/'), throwsStateError);
      dav.fail = null;
      await expectLater(
        cleaner.scan('/dav/', checkCancelled: () => throw StateError('stop')),
        throwsStateError,
      );
      for (final path in ['/dav/', '/other/', '/dav/%2e%2e/other/']) {
        await expectLater(cleaner.clean('/dav/', [path]), throwsA(anything));
      }
      expect(dav.deleted, isEmpty);
    },
  );

  test(
    'large libraries split by work and video count without duplicate subtitles',
    () {
      final entries = [
        for (var i = 0; i < 602; i++)
          DavEntry('/dav/show/season/ep$i.mkv', false),
        const DavEntry('/dav/show/season/ep100.zh.srt', false),
        const DavEntry('/dav/other/ep.mkv', false),
      ];
      final batches = RenameAgent.batches('/dav/', entries);
      expect(batches.length, 8);
      expect(
        batches.every((b) => b.where(RenameAgent.isVideo).length <= 100),
        isTrue,
      );
      expect(
        batches.expand((b) => b).where((e) => e.name.endsWith('.srt')).length,
        1,
      );
    },
  );
}
