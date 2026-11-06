import 'dart:async';
import 'dart:convert';

import 'package:azusa/features/organizer/ai/agent.dart';
import 'package:azusa/features/organizer/ai/folder_layout.dart';
import 'package:azusa/features/organizer/ai/tmdb.dart';
import 'package:azusa/features/organizer/connections/connection_settings.dart';
import 'package:azusa/features/organizer/dav/webdav.dart';
import 'package:azusa/features/organizer/rename_plan.dart';
import 'package:azusa/features/assistant/plan_tree.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const _settings = ConnectionSettings(
  webdavUrl: 'https://nas.test/dav/',
  model: 'test',
  tmdbToken: 'test',
);

class _FolderDav extends WebDavClient {
  _FolderDav(Map<String, DavEntry> files)
    : files = {...files},
      super(_settings);
  final Map<String, DavEntry> files;
  final log = <String>[];

  @override
  Future<List<DavEntry>> list(String path) async {
    if (!files.containsKey(path) && path != '/dav/') {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        response: Response(
          requestOptions: RequestOptions(path: path),
          statusCode: 404,
        ),
      );
    }
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
  Future<DavEntry?> stat(String path) async => files[path];

  @override
  Future<void> mkdir(String path) async {
    log.add('mkdir $path');
    files[path] = DavEntry(path, true);
  }

  @override
  Future<void> move(String from, String to, {String? etag}) async {
    if (!files.containsKey(to.substring(0, to.lastIndexOf('/') + 1)) &&
        to.substring(0, to.lastIndexOf('/') + 1) != '/dav/') {
      throw StateError('父目录不存在');
    }
    log.add('move $from → $to');
    files[to] = DavEntry(to, false);
    files.remove(from);
  }
}

RenameItem _tv(
  String source,
  int season,
  int episode, {
  String title = '绝命毒师',
  int? year = 2008,
}) => RenameItem(
  source: source,
  targetName: '$title - S0${season}E0$episode.mkv',
  tmdbId: 1396,
  tmdbMediaType: TmdbMediaType.tv,
  mediaTitle: title,
  mediaYear: year,
  seasonNumber: season,
  episodeNumber: episode,
  scope: '/dav/',
);

const _movie = RenameItem(
  source: '/dav/raw.mkv',
  targetName: '星际穿越 (2014).mkv',
  tmdbId: 157336,
  tmdbMediaType: TmdbMediaType.movie,
  mediaTitle: '星际穿越',
  mediaYear: 2014,
  scope: '/dav/',
);

String _encoded(List<String> segments) =>
    '/dav/${segments.map((s) => '${Uri.encodeComponent(s)}/').join()}';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);
  final FutureOr<Object> Function(RequestOptions) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(await handler(options)),
    200,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );

  @override
  void close({bool force = false}) {}
}

void main() {
  group('目录规划', () {
    test('多个目录分别输出到各自上一级，切换保留手动编辑和勾选', () {
      const layout = FolderLayout(
        seriesFolders: true,
        seasonFolders: true,
        inParentDirectory: true,
      );
      final scopes = ['/dav/groupA/raw/', '/dav/groupB/raw/'];
      var plan = [
        for (final scope in scopes)
          RenameItem(
            source: '${scope}raw.mkv',
            targetName: 'edited.mkv',
            enabled: scope == scopes.first,
            tmdbMediaType: TmdbMediaType.tv,
            mediaTitle: 'Show',
            seasonNumber: 1,
            scope: scope,
          ),
      ];
      for (final scope in scopes) {
        plan = applyFolderLayout(plan, scope, layout, root: '/dav/');
      }
      expect(plan.map((item) => item.targetDirectory), [
        '/dav/groupA/Show/Season%2001/',
        '/dav/groupB/Show/Season%2001/',
      ]);
      expect(plannedFolders(plan), [
        '/dav/groupA/Show/',
        '/dav/groupA/Show/Season%2001/',
      ]);
      final tree = PlanTree.build(scopes.first, plan, []);
      expect(tree.root.path, '/dav/');
      expect(tree.newDirectories, plannedFolders(plan).toSet());
      for (final scope in scopes) {
        plan = applyFolderLayout(
          plan,
          scope,
          layout.copyWith(inParentDirectory: false),
          root: '/dav/',
        );
      }
      expect(plan.first.targetDirectory, '${scopes.first}Show/Season%2001/');
      expect(plan.first.targetName, 'edited.mkv');
      expect(plan.last.enabled, isFalse);
    });

    test('上一级模式不越过连接根目录，关闭布局不向上移动', () {
      final layout = FolderLayout.full.copyWith(inParentDirectory: true);
      expect(
        applyFolderLayout(
          [_movie],
          '/dav/',
          layout,
          root: '/dav/',
        ).single.targetDirectory,
        _encoded(['星际穿越 (2014)']),
      );
      final flat = applyFolderLayout(
        [_tv('/dav/sub/a.mkv', 1, 1), _movie],
        '/dav/',
        const FolderLayout(inParentDirectory: true),
        root: '/dav/',
      );
      expect(flat.first.targetDirectory, '/dav/');
      expect(flat.last.targetDirectory, isNull);
      expect(plannedFolders(flat), isEmpty);
    });

    test('当前目录已是作品目录时复用，不重复嵌套同名文件夹', () {
      final scope = _encoded(['绝命毒师 (2008)']);
      final item = RenameItem(
        source: '${scope}raw.mkv',
        targetName: '绝命毒师 - S01E01.mkv',
        tmdbMediaType: TmdbMediaType.tv,
        mediaTitle: '绝命毒师',
        mediaYear: 2008,
        seasonNumber: 1,
        scope: scope,
      );
      final full = applyFolderLayout([item], scope, FolderLayout.full);
      expect(full.single.targetDirectory, '${scope}Season%2001/');
      expect(plannedFolders(full), ['${scope}Season%2001/']);
      final noSeasons = applyFolderLayout(
        full,
        scope,
        const FolderLayout(seriesFolders: true),
      );
      expect(noSeasons.single.targetDirectory, scope);
      expect(plannedFolders(noSeasons), isEmpty);
    });

    test('电影目录及只分季的同名当前目录也直接复用', () {
      final movieScope = _encoded(['星际穿越 (2014)']);
      expect(
        plannedDirectory(_movie, movieScope, FolderLayout.full),
        movieScope,
      );
      final seasonScope = _encoded(['Season 01']);
      expect(
        plannedDirectory(
          _tv('${seasonScope}raw.mkv', 1, 1),
          seasonScope,
          const FolderLayout(seasonFolders: true),
        ),
        seasonScope,
      );
    });

    test('完整布局按作品与季生成文件夹，特殊集使用 Specials', () {
      final plan = applyFolderLayout(
        [
          _tv('/dav/a.mkv', 1, 1),
          _tv('/dav/sub/b.mkv', 2, 1),
          _tv('/dav/c.mkv', 0, 1),
          _movie,
        ],
        '/dav/',
        FolderLayout.full,
      );
      expect(plan[0].targetDirectory, _encoded(['绝命毒师 (2008)', 'Season 01']));
      expect(plan[1].targetDirectory, _encoded(['绝命毒师 (2008)', 'Season 02']));
      expect(plan[2].targetDirectory, _encoded(['绝命毒师 (2008)', 'Specials']));
      expect(plan[3].targetDirectory, _encoded(['星际穿越 (2014)']));
      expect(plannedFolders(plan), [
        _encoded(['星际穿越 (2014)']),
        _encoded(['绝命毒师 (2008)']),
        _encoded(['绝命毒师 (2008)', 'Season 01']),
        _encoded(['绝命毒师 (2008)', 'Season 02']),
        _encoded(['绝命毒师 (2008)', 'Specials']),
      ]);
    });

    test('关闭布局时剧集平铺回当前目录，电影保持原位，人工改名保留', () {
      final full = applyFolderLayout(
        [_tv('/dav/sub/b.mkv', 1, 2), _movie],
        '/dav/',
        FolderLayout.full,
      );
      final edited = [full[0].copyWith(targetName: '人工.mkv'), full[1]];
      final none = applyFolderLayout(edited, '/dav/', FolderLayout.none);
      expect(none[0].targetDirectory, '/dav/');
      expect(none[0].targetName, '人工.mkv');
      expect(none[1].targetDirectory, isNull);
      expect(plannedFolders(none), isEmpty);
    });

    test('只分季时不建剧集目录，名称非法字符替换，缺少年份时省略', () {
      final seasons = applyFolderLayout(
        [_tv('/dav/a.mkv', 3, 1)],
        '/dav/',
        const FolderLayout(seasonFolders: true),
      );
      expect(seasons.single.targetDirectory, _encoded(['Season 03']));
      final sanitized = applyFolderLayout(
        [_tv('/dav/a.mkv', 1, 1, title: '22/7', year: null)],
        '/dav/',
        const FolderLayout(seriesFolders: true),
      );
      expect(sanitized.single.targetDirectory, _encoded(['22／7']));
    });

    test('没有作品身份或不在本次范围的项目不移动', () {
      const other = RenameItem(source: '/dav/x.mkv', targetName: 'y.mkv');
      final outside = _tv('/dav/a.mkv', 1, 1).withTargetDirectory(null);
      final plan = applyFolderLayout(
        [other, outside],
        '/dav/sub/',
        FolderLayout.full,
      );
      expect(plan[0].targetDirectory, isNull);
      expect(plan[1].targetDirectory, isNull);
    });
  });

  group('目录执行', () {
    test('上一级模式逐级建目录并移动，冲突时不覆盖', () async {
      const scope = '/dav/raw/';
      const source = '${scope}raw.mkv';
      const item = RenameItem(
        source: source,
        targetName: 'Show.mkv',
        tmdbMediaType: TmdbMediaType.tv,
        mediaTitle: 'Show',
        seasonNumber: 1,
        scope: scope,
      );
      final plan = applyFolderLayout(
        [item],
        scope,
        FolderLayout.full.copyWith(inParentDirectory: true),
        root: '/dav/',
      );
      final dav = _FolderDav({
        scope: const DavEntry(scope, true),
        source: const DavEntry(source, false),
      });
      addTearDown(dav.close);
      final result = await RenameExecutor(dav).execute(plan);
      expect(result.error, isNull);
      expect(dav.log.take(2), [
        'mkdir /dav/Show/',
        'mkdir /dav/Show/Season%2001/',
      ]);
      expect(dav.files.containsKey(plan.single.target), isTrue);
      dav.files[source] = const DavEntry(source, false);
      final before = dav.log.length;
      expect((await RenameExecutor(dav).execute(plan)).error, contains('已存在'));
      expect(dav.log.length, before);
    });

    test('拒绝超出扫描目录上一级的目标范围及连接根目录', () async {
      const source = '/dav/raw/a.mkv';
      const item = RenameItem(
        source: source,
        targetName: 'a.mkv',
        scope: '/dav/raw/',
        destinationScope: '/',
        targetDirectory: '/elsewhere/',
      );
      expect(validatePlan([item], [const DavEntry(source, false)]), '目标目录无效');
      final dav = _FolderDav({source: const DavEntry(source, false)});
      addTearDown(dav.close);
      expect((await RenameExecutor(dav).execute([item])).error, '目标目录无效');
      expect(dav.log, isEmpty);
    });

    test('复用当前作品目录时只创建季目录，执行目标与预览一致', () async {
      final scope = _encoded(['绝命毒师 (2008)']);
      final source = '${scope}raw.mkv';
      final dav = _FolderDav({
        scope: DavEntry(scope, true),
        source: DavEntry(source, false),
      });
      addTearDown(dav.close);
      final plan = applyFolderLayout(
        [
          RenameItem(
            source: source,
            targetName: '绝命毒师 - S01E01.mkv',
            tmdbMediaType: TmdbMediaType.tv,
            mediaTitle: '绝命毒师',
            mediaYear: 2008,
            seasonNumber: 1,
            scope: scope,
          ),
        ],
        scope,
        FolderLayout.full,
      );
      final result = await RenameExecutor(dav).execute(plan);
      expect(result.error, isNull);
      expect(dav.log.where((entry) => entry.startsWith('mkdir')), [
        'mkdir ${scope}Season%2001/',
      ]);
      expect(dav.files.containsKey(plan.single.target), isTrue);
    });

    test('按需逐级创建文件夹后移动，已存在的文件夹不重复创建', () async {
      final existing = _encoded(['绝命毒师 (2008)']);
      final dav = _FolderDav({
        '/dav/a.mkv': const DavEntry('/dav/a.mkv', false),
        '/dav/b.mkv': const DavEntry('/dav/b.mkv', false),
        existing: DavEntry(existing, true),
      });
      addTearDown(dav.close);
      final plan = applyFolderLayout(
        [_tv('/dav/a.mkv', 1, 1), _tv('/dav/b.mkv', 1, 2)],
        '/dav/',
        FolderLayout.full,
      );
      expect(validatePlan(plan, dav.files.values.toList()), isNull);
      final created = <String>[];
      final result = await RenameExecutor(dav)
          .execute(plan, onDirectoryCreated: (path) async => created.add(path));
      expect(result.error, isNull);
      final season = _encoded(['绝命毒师 (2008)', 'Season 01']);
      expect(created, [season]);
      expect(dav.log.first, 'mkdir $season');
      expect(dav.log.where((e) => e.startsWith('mkdir')), hasLength(1));
      expect(dav.files.containsKey(plan[0].target), isTrue);
      expect(dav.files.containsKey(plan[1].target), isTrue);
    });

    test('目标文件夹位置被文件占用时停止且不移动', () async {
      final blocked = _encoded(['星际穿越 (2014)']);
      final dav = _FolderDav({
        '/dav/raw.mkv': const DavEntry('/dav/raw.mkv', false),
        blocked: DavEntry(blocked, false),
      });
      addTearDown(dav.close);
      final plan = applyFolderLayout([_movie], '/dav/', FolderLayout.full);
      final result = await RenameExecutor(dav).execute(plan);
      expect(result.error, contains('同名文件占用'));
      expect(dav.log, isEmpty);
    });

    test('新文件夹中已有同名文件时拒绝执行', () {
      final plan = applyFolderLayout([_movie], '/dav/', FolderLayout.full);
      final folder = plan.single.targetDirectory!;
      final error = validatePlan(plan, [
        const DavEntry('/dav/raw.mkv', false),
        DavEntry(plan.single.target, false),
        DavEntry(folder, true),
      ]);
      expect(error, contains('已存在'));
    });

    test('没有范围的项目不允许移到其他目录', () {
      const item = RenameItem(
        source: '/dav/a.mkv',
        targetName: 'b.mkv',
        targetDirectory: '/dav/other/',
      );
      expect(
        validatePlan([item], [const DavEntry('/dav/a.mkv', false)]),
        '目标目录无效',
      );
      final scoped = _movie.withTargetDirectory('/elsewhere/');
      expect(
        validatePlan([scoped], [const DavEntry('/dav/raw.mkv', false)]),
        '目标目录无效',
      );
    });
  });

  test('Agent 应用目录结构、随视频移动字幕，并只按要求调整结构', () async {
    final prompts = <String>[];
    final ai = Dio()
      ..httpClientAdapter = _Adapter((options) async {
        final body = jsonDecode(
          utf8.decode(
            await (options.data as Stream<List<int>>)
                .expand((bytes) => bytes)
                .toList(),
          ),
        ) as Map;
        final messages = (body['messages'] as List).cast<Map>();
        prompts.add(
          messages.firstWhere((m) => m['role'] == 'system')['content']
              as String,
        );
        if (messages.length <= 2) {
          return {
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': null,
                  'tool_calls': [
                    {
                      'id': 'a',
                      'type': 'function',
                      'function': {
                        'name': 'search_tv',
                        'arguments': '{"query":"Show"}',
                      },
                    },
                    {
                      'id': 'b',
                      'type': 'function',
                      'function': {
                        'name': 'get_season',
                        'arguments': '{"series_id":1,"season_number":1}',
                      },
                    },
                  ],
                },
              },
            ],
          };
        }
        return {
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': jsonEncode({
                  'folders': {'series_folders': false},
                  'items': [
                    {
                      'source': '/dav/Show.S01E01.1080p.mkv',
                      'targetName': 'Show - S01E01.mkv',
                      'media_type': 'tv',
                      'series_id': 1,
                      'season_number': 1,
                      'episode_number': 1,
                    },
                  ],
                }),
              },
            },
          ],
        };
      });
    final data = Dio()
      ..httpClientAdapter = _Adapter(
        (options) => options.path.endsWith('/search/tv')
            ? {
                'results': [
                  {'id': 1, 'name': 'Show', 'first_air_date': '2020-05-01'},
                ],
              }
            : {
                'episodes': [
                  {'id': 1, 'name': 'Pilot', 'episode_number': 1},
                ],
              },
      );
    const entries = [
      DavEntry('/dav/Show.S01E01.1080p.mkv', false),
      DavEntry('/dav/Show.S01E01.zh.srt', false),
      DavEntry('/dav/other.srt', false),
    ];
    final dav = _FolderDav({for (final entry in entries) entry.path: entry});
    final tmdb = TmdbClient(_settings, client: data);
    final agent = RenameAgent(_settings, dav, tmdb, client: ai);
    addTearDown(() {
      agent.close();
      tmdb.close();
      dav.close();
    });
    FolderLayout? reported;
    final plan = await agent.propose(
      '/dav/',
      entries,
      folderLayout: FolderLayout.full,
      onLayout: (layout) => reported = layout,
    );
    expect(prompts.first, contains('series_folders=true'));
    expect(prompts.first, contains('仅当整理要求明确要求调整目录结构时'));
    expect(
      reported,
      const FolderLayout(movieFolders: true, seasonFolders: true),
    );
    expect(plan, hasLength(2));
    expect(plan[0].mediaYear, 2020);
    expect(plan[0].scope, '/dav/');
    expect(plan[0].targetDirectory, _encoded(['Season 01']));
    expect(plan[1].source, '/dav/Show.S01E01.zh.srt');
    expect(plan[1].targetName, 'Show - S01E01.zh.srt');
    expect(plan[1].targetDirectory, _encoded(['Season 01']));
    final result = await RenameExecutor(dav).execute(plan);
    expect(result.error, isNull);
    expect(result.completed, hasLength(2));
    expect(dav.files.containsKey(plan[1].source), isFalse);
    expect(dav.files.containsKey(plan[1].target), isTrue);
    expect(dav.files.containsKey('/dav/other.srt'), isTrue);
  });
}
