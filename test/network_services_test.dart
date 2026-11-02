import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:azusa/core/settings/naming_language.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:azusa/features/organizer/ai/agent.dart';
import 'package:azusa/features/organizer/connections/connection_settings.dart';
import 'package:azusa/features/organizer/connections/http_clients.dart';
import 'package:azusa/features/organizer/ai/langchain_http_client.dart';
import 'package:http/http.dart' as http;
import 'package:azusa/features/organizer/ai/tmdb.dart';
import 'package:azusa/features/organizer/dav/webdav.dart';
import 'package:azusa/features/organizer/rename_plan.dart';

class TestAdapter implements HttpClientAdapter {
  TestAdapter(this.handler);
  final FutureOr<ResponseBody> Function(RequestOptions options) handler;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async => handler(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody jsonResponse(Object data) => ResponseBody.fromString(
  jsonEncode(data),
  200,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);

String listing(String href, {bool collection = false, int status = 200}) =>
    '''
<d:response><d:href>$href</d:href><d:propstat><d:prop>
<d:resourcetype>${collection ? '<d:collection/>' : ''}</d:resourcetype>
<d:getetag>"v1"</d:getetag><d:getcontentlength>42</d:getcontentlength>
</d:prop><d:status>HTTP/1.1 $status OK</d:status></d:propstat></d:response>''';

void main() {
  for (final language in NamingLanguage.values) {
    test('TMDB 搜索和季查询使用命名语言 ${language.code}', () async {
      final paths = <String>[];
      final dio = Dio()
        ..httpClientAdapter = TestAdapter((options) {
          paths.add(options.path);
          expect(options.queryParameters['language'], language.code);
          return jsonResponse({'results': [], 'episodes': []});
        });
      final tmdb = TmdbClient(
        const ConnectionSettings(tmdbToken: 'test'),
        client: dio,
        namingLanguage: language,
      );
      addTearDown(tmdb.close);
      await tmdb.search('Breaking Bad');
      await tmdb.season(1396, 1);
      expect(paths, hasLength(2));
    });

    test('AI 系统指令使用命名语言 ${language.code} 并优先于整理要求', () async {
      var requests = 0;
      final ai = Dio()
        ..httpClientAdapter = TestAdapter((options) async {
          requests++;
          final stream = options.data as Stream<List<int>>;
          final body = jsonDecode(
            utf8.decode(await stream.expand((bytes) => bytes).toList()),
          ) as Map;
          final messages = (body['messages'] as List).cast<Map>();
          final system = messages.firstWhere((m) => m['role'] == 'system');
          expect(
            system['content'],
            contains('${language.label}（${language.code}）'),
          );
          expect(system['content'], contains('不自行翻译或编造标题'));
          expect(system['content'], contains('不得覆盖此命名语言设置'));
          final user = messages.firstWhere((m) => m['role'] == 'user');
          expect(user['content'], contains('使用其他语言'));
          return jsonResponse({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': '{"items":[]}'},
              },
            ],
          });
        });
      const settings = ConnectionSettings(
        webdavUrl: 'https://nas.test/dav/',
        model: 'test',
      );
      final dav = WebDavClient(settings);
      final tmdb = TmdbClient(settings, namingLanguage: language);
      final agent = RenameAgent(settings, dav, tmdb, client: ai);
      addTearDown(() {
        agent.close();
        tmdb.close();
        dav.close();
      });
      expect(
        await agent.propose('/dav/', [
          const DavEntry('/dav/a.mkv', false),
        ], instruction: '使用其他语言'),
        isEmpty,
      );
      expect(requests, 1);
    });
  }

  test('HTTP 适配层读取 usage 不影响 SDK 正文，忽略失败响应', () async {
    var responses = 0;
    final dio = Dio()
      ..httpClientAdapter = TestAdapter(
        (_) => jsonResponse({
          'usage': {'prompt_tokens': 100, 'completion_tokens': 20},
        }),
      );
    final client = LangChainHttpClient(
      dio,
      onChatResponse: (body, elapsed) {
        responses++;
        expect((body['usage'] as Map)['prompt_tokens'], 100);
        expect(elapsed.inMicroseconds, greaterThan(0));
      },
    );
    addTearDown(client.close);
    final result = await client.post(
      Uri.parse('https://ai.test/v1/chat/completions'),
    );
    expect((jsonDecode(result.body)['usage'] as Map)['completion_tokens'], 20);
    expect(responses, 1);
    dio.httpClientAdapter = TestAdapter(
      (_) => ResponseBody.fromString('{}', 429),
    );
    await client.post(Uri.parse('https://ai.test/v1/chat/completions'));
    expect(responses, 1);
  });

  test('LangChain HTTP 适配层走实际代理并保留请求正文', () async {
    final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => proxy.close(force: true));
    final bodies = <String>[];
    proxy.listen((request) async {
      bodies.add(await utf8.decoder.bind(request).join());
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"ok":true}');
      await request.response.close();
    });
    final client = LangChainHttpClient(
      createServiceClient(
        ConnectionSettings(proxyUrl: 'http://127.0.0.1:${proxy.port}'),
      ),
    );
    addTearDown(client.close);
    final result = await client.post(
      Uri.parse('http://ai.invalid/v1/chat/completions'),
      headers: {'Content-Type': 'application/json'},
      body: '{"model":"custom-model"}',
    );
    expect(result.statusCode, 200);
    expect(jsonDecode(result.body), {'ok': true});
    expect(bodies, ['{"model":"custom-model"}']);
  });

  test('LangChain HTTP 适配层不跟随重定向且关闭后拒绝请求', () async {
    final dio = Dio()
      ..httpClientAdapter = TestAdapter((options) {
        expect(options.followRedirects, isFalse);
        return ResponseBody.fromString(
          '',
          302,
          headers: {
            'location': ['https://untrusted.test'],
          },
        );
      });
    final client = LangChainHttpClient(dio);
    expect(
      (await client.get(Uri.parse('https://ai.test/v1/models'))).statusCode,
      302,
    );
    client.close();
    await expectLater(
      client.get(Uri.parse('https://ai.test/v1/models')),
      throwsA(isA<http.ClientException>()),
    );
  });

  test('LangChain AgentExecutor 在 8 轮后停止工具循环', () async {
    var requests = 0;
    final ai = Dio()
      ..httpClientAdapter = TestAdapter((_) {
        requests++;
        return jsonResponse({
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': null,
                'tool_calls': [
                  {
                    'id': 'call$requests',
                    'type': 'function',
                    'function': {
                      'name': 'search_tv',
                      'arguments': '{"query":"test"}',
                    },
                  },
                ],
              },
            },
          ],
        });
      });
    final data = Dio()
      ..httpClientAdapter = TestAdapter((_) => jsonResponse({'results': []}));
    const settings = ConnectionSettings(
      webdavUrl: 'https://nas.test/dav/',
      model: 'test',
      tmdbToken: 'test',
    );
    final dav = WebDavClient(settings);
    final tmdb = TmdbClient(settings, client: data);
    final agent = RenameAgent(settings, dav, tmdb, client: ai);
    addTearDown(() {
      agent.close();
      tmdb.close();
      dav.close();
    });
    await expectLater(
      agent.propose('/dav/', [const DavEntry('/dav/a.mkv', false)]),
      throwsStateError,
    );
    expect(requests, 8);
  });
  test('AI 建议自动清理非法字符、保留原扩展名并显示明确匹配结果', () async {
    var requests = 0;
    final ai = Dio()
      ..httpClientAdapter = TestAdapter((_) {
        requests++;
        return jsonResponse({
          'choices': [
            {
              'message': requests == 1
                  ? {
                      'role': 'assistant',
                      'content': null,
                      'tool_calls': [
                        {
                          'id': 'season',
                          'type': 'function',
                          'function': {
                            'name': 'get_season',
                            'arguments':
                                '{"series_id":93875,"season_number":1}',
                          },
                        },
                      ],
                    }
                  : {
                      'role': 'assistant',
                      'content': jsonEncode({
                        'items': [
                          {
                            'source': '/dav/22%20-%20S01E12.MP4',
                            'targetName': '22 / 7 - S01E12 - 22/7.mkv. ',
                            'series_id': 93875,
                            'season_number': 1,
                            'episode_number': 12,
                            'reason': '剧名和集数与 TMDB 第1季第12集一致',
                          },
                        ],
                      }),
                    },
            },
          ],
        });
      });
    final data = Dio()
      ..httpClientAdapter = TestAdapter(
        (_) => jsonResponse({
          'episodes': [
            {'episode_number': 12, 'name': '22/7'},
          ],
        }),
      );
    const settings = ConnectionSettings(
      webdavUrl: 'https://nas.test/dav/',
      model: 'test',
      tmdbToken: 'test',
    );
    final dav = WebDavClient(settings);
    final tmdb = TmdbClient(settings, client: data);
    final agent = RenameAgent(settings, dav, tmdb, client: ai);
    addTearDown(() {
      agent.close();
      tmdb.close();
      dav.close();
    });
    const entries = [DavEntry('/dav/22%20-%20S01E12.MP4', false, etag: 'v1')];
    final plan = await agent.propose('/dav/', entries);
    expect(plan, hasLength(1));
    expect(plan.single.source, entries.single.path);
    expect(plan.single.targetName, '22 ／ 7 - S01E12 - 22／7.MP4');
    expect(plan.single.reason, '匹配结果：第 1 季第 12 集 · 22/7\nTMDB 93875');
    expect(plan.single.fingerprint, entries.single.fingerprint);
    expect(plan.single.etag, 'v1');
    expect(validatePlan(plan, entries), isNull);
    expect(requests, 2);
  });

  test('TMDB 自动区分 API Key 和 Bearer Token', () async {
    for (final credential in ['example-api-key', 'header.payload.signature']) {
      final dio = Dio()
        ..httpClientAdapter = TestAdapter((options) {
          if (credential.contains('.')) {
            expect(options.headers['Authorization'], 'Bearer $credential');
            expect(options.queryParameters.containsKey('api_key'), isFalse);
          } else {
            expect(options.queryParameters['api_key'], credential);
            expect(options.headers.containsKey('Authorization'), isFalse);
          }
          return jsonResponse({'results': []});
        });
      final tmdb = TmdbClient(
        ConnectionSettings(tmdbToken: credential),
        client: dio,
      );
      try {
        await tmdb.search('Breaking Bad');
      } finally {
        tmdb.close();
      }
    }
  });
  test('WebDAV 解析中文名称、只返回直属子项、忽略失败属性', () async {
    final dio = Dio()
      ..httpClientAdapter = TestAdapter((options) {
        expect(options.method, 'PROPFIND');
        expect(options.headers['Depth'], '1');
        return ResponseBody.fromString(
          '<d:multistatus xmlns:d="DAV:">'
          '${listing('/dav/', collection: true)}'
          '${listing('/dav/%E5%89%A7%E9%9B%86%201.mkv')}'
          '${listing('/dav/sub/', collection: true)}'
          '${listing('/dav/%23recycle/', collection: true)}'
          '${listing('/dav/__MACOSX/', collection: true)}'
          '${listing('/dav/.config/', collection: true)}'
          '${listing('/dav/.local/', collection: true)}'
          '${listing('/dav/.xterminal/', collection: true)}'
          '${listing('/dav/.episode.mkv')}'
          '${listing('/dav/sub/hidden.mkv')}'
          '${listing('/dav/denied.mkv', status: 403)}'
          '</d:multistatus>',
          207,
        );
      });
    final dav = WebDavClient(
      const ConnectionSettings(webdavUrl: 'https://nas.test/dav/'),
      client: dio,
    );
    addTearDown(dav.close);
    final entries = await dav.list('/dav/');
    expect(entries.map((e) => e.name), ['sub', '.episode.mkv', '剧集 1.mkv']);
    expect(entries.last.etag, '"v1"');
  });

  test('MOVE 不覆盖且携带 ETag 条件', () async {
    final dio = Dio()
      ..httpClientAdapter = TestAdapter((options) {
        expect(options.method, 'MOVE');
        expect(options.headers['Overwrite'], 'F');
        expect(options.headers['If-Match'], '"old"');
        expect(options.headers['Destination'], 'https://nas.test/dav/new.mkv');
        return ResponseBody.fromString('', 201);
      });
    final dav = WebDavClient(
      const ConnectionSettings(webdavUrl: 'https://nas.test/dav/'),
      client: dio,
    );
    addTearDown(dav.close);
    await dav.move('/dav/a.mkv', '/dav/new.mkv', etag: '"old"');
  });

  test('实际 HTTP 请求走配置代理且直连开关有效', () async {
    final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => proxy.close(force: true));
    final requests = <String>[];
    proxy.listen((request) async {
      requests.add(request.uri.toString());
      request.response.write('proxied');
      await request.response.close();
    });
    final settings = ConnectionSettings(
      proxyUrl: 'http://127.0.0.1:${proxy.port}',
    );
    final dio = createServiceClient(settings);
    addTearDown(() => dio.close(force: true));
    expect(
      (await dio.get<String>('http://ai.invalid/v1/models')).data,
      'proxied',
    );
    expect(requests.single, 'http://ai.invalid/v1/models');
    expect(usesProxy(settings, NetworkService.tmdb), isTrue);
    expect(usesProxy(settings, NetworkService.webdav), isFalse);
  });

  test('拒绝无效代理及携带明文密码的代理地址', () {
    for (final value in [
      'socks5://localhost:1',
      'http://localhost',
      'http://u:p@localhost:1',
      'http://localhost:0',
    ]) {
      expect(() => validatedProxy(value), throwsFormatException);
    }
  });

  test('Agent 回传工具结果后仅输出有 TMDB 依据的计划', () async {
    var round = 0;
    final ai = Dio()
      ..httpClientAdapter = TestAdapter((options) async {
        expect(options.uri.path, '/v1/chat/completions');
        final data = options.data;
        final body = data is Stream<List<int>>
            ? jsonDecode(
                utf8.decode(await data.expand((bytes) => bytes).toList()),
              ) as Map
            : data as Map;
        expect(body['model'], 'custom-model');
        final messages = body['messages'] as List;
        if (round++ == 0) {
          return jsonResponse({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': null,
                  'tool_calls': [
                    {
                      'id': 'call1',
                      'type': 'function',
                      'function': {
                        'name': 'get_season',
                        'arguments': '{"series_id":1396,"season_number":1}',
                      },
                    },
                  ],
                },
              },
            ],
          });
        }
        expect((messages.last as Map)['role'], 'tool');
        expect((messages.last as Map)['tool_call_id'], 'call1');
        return jsonResponse({
          'choices': [
            {
              'message': {
                'content': jsonEncode({
                  'items': [
                    {
                      'source': '/dav/a.mkv',
                      'targetName': '绝命毒师 - S01E01.mkv',
                      'series_id': 1396,
                      'season_number': 1,
                      'episode_number': 1,
                      'reason': '匹配文件集数',
                    },
                  ],
                }),
              },
            },
          ],
        });
      });
    final tmdbDio = Dio()
      ..httpClientAdapter = TestAdapter(
        (options) => jsonResponse({
          'episodes': [
            {'id': 1, 'episode_number': 1, 'season_number': 1, 'name': 'Pilot'},
          ],
        }),
      );
    const settings = ConnectionSettings(
      webdavUrl: 'https://nas.test/dav/',
      aiUrl: 'http://localhost/v1',
      model: 'custom-model',
      tmdbToken: 'test',
    );
    final dav = WebDavClient(settings);
    final tmdb = TmdbClient(settings, client: tmdbDio);
    final agent = RenameAgent(settings, dav, tmdb, client: ai);
    addTearDown(() {
      agent.close();
      dav.close();
      tmdb.close();
    });
    final plan = await agent.propose('/dav/', [
      const DavEntry('/dav/a.mkv', false),
    ]);
    expect(plan.single.reason, contains('TMDB 1396'));
    expect(plan.single.targetName, '绝命毒师 - S01E01.mkv');
    expect(round, 2);
  });

  test('Agent 未查询 TMDB 的猜测不能进入预览', () async {
    final ai = Dio()
      ..httpClientAdapter = TestAdapter(
        (_) => jsonResponse({
          'choices': [
            {
              'message': {
                'content': '{"items":[{"source":"/dav/a.mkv","targetName":"new.mkv","series_id":1,"season_number":1,"episode_number":1}]}',
              },
            },
          ],
        }),
      );
    const settings = ConnectionSettings(
      webdavUrl: 'https://nas.test/dav/',
      model: 'test',
    );
    final dav = WebDavClient(settings);
    final tmdb = TmdbClient(settings);
    final agent = RenameAgent(settings, dav, tmdb, client: ai);
    addTearDown(() {
      agent.close();
      dav.close();
      tmdb.close();
    });
    await expectLater(
      agent.propose('/dav/', [const DavEntry('/dav/a.mkv', false)]),
      throwsFormatException,
    );
  });
}
