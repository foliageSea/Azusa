import 'dart:async';
import 'dart:convert';

import 'package:azusa/core/settings/naming_language.dart';
import 'package:azusa/core/settings/naming_format.dart';
import 'package:azusa/features/organizer/ai/agent.dart';
import 'package:azusa/features/organizer/ai/tmdb.dart';
import 'package:azusa/features/organizer/connections/connection_settings.dart';
import 'package:azusa/features/organizer/dav/webdav.dart';
import 'package:azusa/features/organizer/rename_plan.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

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

const _settings = ConnectionSettings(
  webdavUrl: 'https://nas.test/dav/',
  model: 'test',
  tmdbToken: 'test',
);

const _movie = {
  'id': 912649,
  'title': '毒液：最后一舞',
  'original_title': 'Venom: The Last Dance',
  'release_date': '2024-10-22',
};

Future<List<RenameItem>> _propose(
  List<DavEntry> entries,
  List<Map<String, Object>> items, {
  bool verify = true,
  bool searchOnly = false,
  NamingFormat namingFormat = NamingFormat.standard,
}) async {
  var round = 0;
  final ai = Dio()
    ..httpClientAdapter = _Adapter(
      (_) => {
        'choices': [
          {
            'message': verify && round++ == 0
                ? {
                    'role': 'assistant',
                    'content': null,
                    'tool_calls': [
                      {
                        'id': 'movie',
                        'type': 'function',
                        'function': {
                          'name': searchOnly ? 'search_movie' : 'get_movie',
                          'arguments': searchOnly
                              ? '{"query":"Venom","year":2024}'
                              : '{"movie_id":912649}',
                        },
                      },
                    ],
                  }
                : {
                    'role': 'assistant',
                    'content': jsonEncode({'items': items}),
                  },
          },
        ],
      },
    );
  final data = Dio()
    ..httpClientAdapter = _Adapter(
      (options) => options.path.endsWith('/search/movie')
          ? {
              'results': [_movie],
            }
          : _movie,
    );
  final dav = WebDavClient(_settings);
  final tmdb = TmdbClient(_settings, client: data);
  final agent = RenameAgent(
    _settings,
    dav,
    tmdb,
    client: ai,
    namingFormat: namingFormat,
  );
  try {
    return await agent.propose('/dav/', entries);
  } finally {
    agent.close();
    tmdb.close();
    dav.close();
  }
}

Map<String, Object> _item(String source) => {
  'source': source,
  'targetName': '毒液：最后一舞 (2024).mkv',
  'media_type': 'movie',
  'movie_id': 912649,
};

void main() {
  for (final language in NamingLanguage.values) {
    test('电影搜索按年份筛选，搜索和详情使用命名语言 ${language.code}', () async {
      final paths = <String>[];
      final dio = Dio()
        ..httpClientAdapter = _Adapter((options) {
          paths.add(options.uri.path);
          expect(options.queryParameters['language'], language.code);
          if (options.path.endsWith('/search/movie')) {
            expect(options.queryParameters['query'], 'Venom');
            expect(options.queryParameters['year'], 2024);
            return {
              'results': [_movie],
            };
          }
          return _movie;
        });
      final tmdb = TmdbClient(_settings, client: dio, namingLanguage: language);
      addTearDown(tmdb.close);
      expect(
        (await tmdb.searchMovies('Venom', year: 2024)).single,
        containsPair('id', 912649),
      );
      expect(await tmdb.movie(912649), containsPair('title', '毒液：最后一舞'));
      expect(paths, ['/3/search/movie', '/3/movie/912649']);
    });
  }

  test('电影和配对字幕原地改名，保留扩展名、语言和指纹', () async {
    const entries = [
      DavEntry('/dav/raw.MKV', false, etag: 'v1'),
      DavEntry('/dav/raw.zh-Hans.srt', false),
      DavEntry('/dav/unrelated.srt', false),
    ];
    final plan = await _propose(entries, [_item(entries.first.path)]);
    expect(plan, hasLength(2));
    expect(plan.first.targetName, '毒液：最后一舞 (2024).MKV');
    expect(plan.first.reason, '电影匹配：毒液：最后一舞 · 2024-10-22\nTMDB 912649');
    expect(plan.first.etag, 'v1');
    expect(
      plan.first.tmdbUrl.toString(),
      'https://www.themoviedb.org/movie/912649',
    );
    expect(plan.last.tmdbUrl, plan.first.tmdbUrl);
    expect(plan.first.fingerprint, entries.first.fingerprint);
    expect(plan.last.targetName, '毒液：最后一舞 (2024).zh-Hans.srt');
    expect(validatePlan(plan, entries), isNull);
  });

  for (final format in NamingFormat.values) {
    test('${format.name} 格式的电影配对字幕跟随视频并保留语言标记', () async {
      const entries = [
        DavEntry('/dav/raw.MKV', false),
        DavEntry('/dav/raw.zh-Hans.srt', false),
      ];
      final dotted =
          format == NamingFormat.dotted || format == NamingFormat.dottedCompact;
      final stem = dotted ? '毒液：最后一舞.2024' : '毒液：最后一舞 (2024)';
      final plan = await _propose(entries, [
        {..._item(entries.first.path), 'targetName': '$stem.mkv'},
      ], namingFormat: format);
      expect(plan.first.targetName, '$stem.MKV');
      expect(plan.last.targetName, '$stem.zh-Hans.srt');
      expect(validatePlan(plan, entries), isNull);
    });
  }

  test('电影子目录保持原位，不沿用剧集平铺行为', () async {
    const entries = [
      DavEntry('/dav/Venom.2024/', true),
      DavEntry('/dav/Venom.2024/raw.mkv', false),
      DavEntry('/dav/Venom.2024/raw.en.srt', false),
    ];
    final plan = await _propose(entries, [_item(entries[1].path)]);
    expect(plan, hasLength(2));
    for (final item in plan) {
      expect(item.targetDirectory, isNull);
      expect(item.target, startsWith('/dav/Venom.2024/'));
    }
    expect(validatePlan(plan, entries), isNull);
  });

  for (final searchOnly in [false, true]) {
    test(searchOnly ? '仅电影搜索结果不能作为详情依据' : '未查询的电影不能进入预览', () async {
      await expectLater(
        _propose(
          [const DavEntry('/dav/raw.mkv', false)],
          [_item('/dav/raw.mkv')],
          verify: searchOnly,
          searchOnly: searchOnly,
        ),
        throwsFormatException,
      );
    });
  }

  test('电影多版本目标重名仍被执行校验阻止', () async {
    const entries = [
      DavEntry('/dav/a.mkv', false),
      DavEntry('/dav/b.mkv', false),
    ];
    final plan = await _propose(entries, [
      _item(entries.first.path),
      _item(entries.last.path),
    ]);
    expect(validatePlan(plan, entries), startsWith('目标文件名重复'));
  });

  test('字幕可匹配多个电影版本时不自动改名', () async {
    const entries = [
      DavEntry('/dav/raw.mkv', false),
      DavEntry('/dav/raw.en.mp4', false),
      DavEntry('/dav/raw.en.srt', false),
    ];
    final plan = await _propose(entries, [_item(entries.first.path)]);
    expect(plan, hasLength(1));
  });

  test('电影与剧集可在同一批建议中分别核验', () async {
    var round = 0;
    final ai = Dio()
      ..httpClientAdapter = _Adapter(
        (_) => {
          'choices': [
            {
              'message': round++ == 0
                  ? {
                      'role': 'assistant',
                      'content': null,
                      'tool_calls': [
                        for (final tool in [
                          ('movie', 'get_movie', '{"movie_id":912649}'),
                          (
                            'tv',
                            'get_season',
                            '{"series_id":1396,"season_number":1}',
                          ),
                        ])
                          {
                            'id': tool.$1,
                            'type': 'function',
                            'function': {'name': tool.$2, 'arguments': tool.$3},
                          },
                      ],
                    }
                  : {
                      'role': 'assistant',
                      'content': jsonEncode({
                        'items': [
                          _item('/dav/movie.mkv'),
                          {
                            'source': '/dav/tv.mkv',
                            'targetName': '绝命毒师 - S01E01.mkv',
                            'media_type': 'tv',
                            'series_id': 1396,
                            'season_number': 1,
                            'episode_number': 1,
                          },
                        ],
                      }),
                    },
            },
          ],
        },
      );
    final data = Dio()
      ..httpClientAdapter = _Adapter(
        (options) => options.path.contains('/season/')
            ? {
                'episodes': [
                  {'episode_number': 1, 'name': 'Pilot'},
                ],
              }
            : _movie,
      );
    final dav = WebDavClient(_settings);
    final tmdb = TmdbClient(_settings, client: data);
    final agent = RenameAgent(_settings, dav, tmdb, client: ai);
    addTearDown(() {
      agent.close();
      tmdb.close();
      dav.close();
    });
    const entries = [
      DavEntry('/dav/movie.mkv', false),
      DavEntry('/dav/tv.mkv', false),
    ];
    final plan = await agent.propose('/dav/', entries);
    expect(plan, hasLength(2));
    expect(plan.first.reason, contains('电影匹配'));
    expect(plan.last.reason, contains('第 1 季第 1 集'));
    expect(validatePlan(plan, entries), isNull);
  });

  test('错误电影详情与无效参数不能成为核验依据', () async {
    final dio = Dio()..httpClientAdapter = _Adapter((_) => {'id': 1});
    final tmdb = TmdbClient(_settings, client: dio);
    addTearDown(tmdb.close);
    await expectLater(tmdb.movie(912649), throwsFormatException);
    await expectLater(tmdb.movie(0), throwsFormatException);
    await expectLater(tmdb.searchMovies(''), throwsFormatException);
    await expectLater(
      tmdb.searchMovies('Venom', year: -1),
      throwsFormatException,
    );
  });
}
