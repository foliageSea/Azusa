import 'dart:async';
import 'dart:convert';

import 'package:azusa/features/assistant/assistant_state.dart';
import 'package:azusa/features/organizer/ai/agent.dart';
import 'package:azusa/features/organizer/ai/agent_activity.dart';
import 'package:azusa/features/organizer/ai/folder_layout.dart';
import 'package:azusa/features/organizer/ai/ai_usage.dart';
import 'package:azusa/features/organizer/ai/tmdb.dart';
import 'package:azusa/features/organizer/connections/connection_settings.dart';
import 'package:azusa/features/organizer/dav/webdav.dart';
import 'package:azusa/features/organizer/organizer_state.dart';
import 'package:azusa/features/organizer/rename_plan.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

Map<String, Object?> _toolCalls(List<(String, String)> calls) => {
  'choices': [
    {
      'message': {
        'role': 'assistant',
        'content': null,
        'tool_calls': [
          for (final (index, (name, arguments)) in calls.indexed)
            {
              'id': 'call-$index',
              'type': 'function',
              'function': {'name': name, 'arguments': arguments},
            },
        ],
      },
    },
  ],
};

class _Connections extends ConnectionSettingsController {
  @override
  Future<ConnectionSettings> build() async => _settings;
}

class _ScriptedOrganizer extends OrganizerController {
  _ScriptedOrganizer(this.results);
  final List<List<RenameItem>> results;
  final instructions = <String>[];
  var executed = 0;

  @override
  OrganizerState build() => const OrganizerState(
    directory: '/dav/',
    entries: [DavEntry('/dav/a.mkv', false), DavEntry('/dav/b.mkv', false)],
  );

  @override
  Future<void> propose({
    String instruction = '',
    FolderLayout? folderLayout,
    void Function(AgentActivity activity)? onActivity,
    void Function(FolderLayout layout)? onLayout,
  }) async {
    instructions.add(instruction);
    const scan = AgentActivity(key: 'scan', kind: AgentActivityKind.scan);
    onActivity?.call(scan);
    onActivity?.call(scan.succeed(count: 2));
    const search = AgentActivity(
      key: 'tool-1',
      kind: AgentActivityKind.searchTv,
      subject: 'Show',
    );
    onActivity?.call(search);
    final plan = results[instructions.length - 1];
    state = state.copyWith(
      plan: plan,
      aiUsage: const AiUsage(inputTokens: 10, outputTokens: 5, responses: 1),
      message: plan.isEmpty ? '未找到可靠的重命名建议，请补充片名和年份或剧名和季数后重试' : '建议已生成',
    );
  }

  @override
  Future<void> execute() async {
    executed++;
    state = state.copyWith(plan: [], message: '已完成 2 项');
  }
}

RenameItem _episode(String source, int episode) => RenameItem(
  source: source,
  targetName: 'Show - S01E0$episode.mkv',
  tmdbId: 1,
  tmdbMediaType: TmdbMediaType.tv,
  mediaTitle: 'Show',
  seasonNumber: 1,
  episodeNumber: episode,
);

void main() {
  test('Agent 按真实工具调用上报活动并在建议中保留结构化身份', () async {
    var round = 0;
    final ai = Dio()
      ..httpClientAdapter = _Adapter((_) {
        switch (round++) {
          case 0:
            return _toolCalls([('search_tv', '{"query":"Show"}')]);
          case 1:
            return _toolCalls([
              ('get_season', '{"series_id":1,"season_number":1}'),
              ('get_movie', '{"movie_id":0}'),
            ]);
          default:
            return {
              'choices': [
                {
                  'message': {
                    'role': 'assistant',
                    'content': jsonEncode({
                      'items': [
                        {
                          'source': '/dav/a.mkv',
                          'targetName': 'Show - S01E01 - Pilot.mkv',
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
        }
      });
    final data = Dio()
      ..httpClientAdapter = _Adapter(
        (options) => options.path.endsWith('/search/tv')
            ? {
                'results': [
                  {'id': 1, 'name': 'Show', 'first_air_date': '2020-01-01'},
                ],
              }
            : {
                'episodes': [
                  {
                    'id': 10,
                    'name': 'Pilot',
                    'episode_number': 1,
                    'season_number': 1,
                  },
                  {
                    'id': 11,
                    'name': 'Second',
                    'episode_number': 2,
                    'season_number': 1,
                  },
                ],
              },
      );
    final dav = WebDavClient(_settings);
    final tmdb = TmdbClient(_settings, client: data);
    final agent = RenameAgent(_settings, dav, tmdb, client: ai);
    final events = <AgentActivity>[];
    addTearDown(() {
      agent.close();
      tmdb.close();
      dav.close();
    });

    final plan = await agent.propose('/dav/', [
      const DavEntry('/dav/a.mkv', false),
    ], onActivity: events.add);

    final latest = <String, AgentActivity>{
      for (final event in events) event.key: event,
    };
    final models = latest.values
        .where((a) => a.kind == AgentActivityKind.model)
        .toList();
    expect(models, hasLength(3));
    expect(
      models.every((a) => a.status == AgentActivityStatus.succeeded),
      isTrue,
    );
    final search = latest.values.singleWhere(
      (a) => a.kind == AgentActivityKind.searchTv,
    );
    expect(search.subject, 'Show');
    expect(search.count, 1);
    expect(search.status, AgentActivityStatus.succeeded);
    final season = latest.values.singleWhere(
      (a) => a.kind == AgentActivityKind.getSeason,
    );
    expect(season.subject, 'Show');
    expect(season.number, 1);
    expect(season.count, 2);
    final movie = latest.values.singleWhere(
      (a) => a.kind == AgentActivityKind.getMovie,
    );
    expect(movie.status, AgentActivityStatus.failed);
    expect(movie.error, isNotEmpty);
    expect(
      events.any(
        (a) =>
            a.kind == AgentActivityKind.searchTv &&
            a.status == AgentActivityStatus.running,
      ),
      isTrue,
    );

    expect(plan.single.mediaTitle, 'Show');
    expect(plan.single.seasonNumber, 1);
    expect(plan.single.episodeNumber, 1);
    final edited = plan.single.copyWith(targetName: 'x.mkv', enabled: false);
    expect(edited.mediaTitle, 'Show');
    expect(edited.seasonNumber, 1);
    expect(edited.episodeNumber, 1);
  });

  group('对话助手', () {
    late ProviderContainer container;
    late _ScriptedOrganizer organizer;

    setUp(() async {
      organizer = _ScriptedOrganizer([
        [_episode('/dav/a.mkv', 1), _episode('/dav/b.mkv', 2)],
        [_episode('/dav/a.mkv', 1)],
        [],
      ]);
      container = ProviderContainer(
        overrides: [
          connectionSettingsProvider.overrideWith(_Connections.new),
          organizerProvider.overrideWith(() => organizer),
        ],
      );
      await container.read(connectionSettingsProvider.future);
    });

    tearDown(() => container.dispose());

    test('未授权时不发送，授权后累积要求并生成递增版本的方案', () async {
      final assistant = container.read(assistantProvider.notifier);
      await assistant.send('整理目录');
      expect(organizer.instructions, isEmpty);
      expect(container.read(assistantProvider).messages, isEmpty);

      assistant.grantConsent();
      await assistant.send('  整理目录  ');
      await assistant.send('只保留第一集');
      expect(organizer.instructions, ['整理目录', '整理目录\n只保留第一集']);

      final messages = container.read(assistantProvider).messages;
      expect(messages.map((m) => m.runtimeType), [
        AssistantUserMessage,
        AssistantRun,
        AssistantReply,
        AssistantUserMessage,
        AssistantRun,
        AssistantReply,
      ]);
      final first = messages[2] as AssistantReply;
      final second = messages[5] as AssistantReply;
      expect(first.planVersion, 1);
      expect(first.revised, isFalse);
      expect(first.summary!.series, 1);
      expect(first.summary!.changes, 2);
      expect(second.planVersion, 2);
      expect(second.revised, isTrue);
      expect(container.read(assistantProvider).planVersion, 2);

      final run = messages[1] as AssistantRun;
      expect(run.status, AssistantRunStatus.succeeded);
      expect(run.lookups, 1);
      expect(
        run.activities.every((a) => a.status != AgentActivityStatus.running),
        isTrue,
      );
      expect(run.usage!.inputTokens, 10);
    });

    test('没有可靠结果时不生成方案版本，执行结果追加到对话', () async {
      final assistant = container.read(assistantProvider.notifier)
        ..grantConsent();
      await assistant.send('整理');
      await assistant.execute();
      expect(organizer.executed, 1);
      final executed = container.read(assistantProvider).messages.last;
      expect(executed, isA<AssistantReply>());
      expect((executed as AssistantReply).kind, AssistantReplyKind.executed);
      expect(executed.detail, '已完成 2 项');
      expect(executed.planVersion, isNull);

      await assistant.send('再试一次');
      await assistant.send('第三次');
      final last = container.read(assistantProvider).messages.last;
      expect((last as AssistantReply).kind, AssistantReplyKind.empty);
      expect(last.planVersion, isNull);
      expect(container.read(assistantProvider).planVersion, 2);
    });

    test('新建会话清空方案与分析状态，保留目录、授权和结构偏好', () async {
      final assistant = container.read(assistantProvider.notifier)
        ..grantConsent();
      await assistant.send('整理');
      assistant.setLayout(const FolderLayout(seriesFolders: true));
      final before = container.read(organizerProvider);
      expect(before.plan, isNotEmpty);
      expect(before.aiUsage, isNotNull);

      assistant.reset();

      final organizerState = container.read(organizerProvider);
      expect(organizerState.plan, isEmpty);
      expect(organizerState.analysisEntries, isEmpty);
      expect(organizerState.aiUsage, isNull);
      expect(organizerState.pricing, isNull);
      expect(organizerState.message, isEmpty);
      expect(organizerState.progress, isEmpty);
      expect(organizerState.directory, before.directory);
      expect(organizerState.entries, before.entries);
      expect(container.read(assistantProvider).messages, isEmpty);
      expect(container.read(assistantProvider).planVersion, 0);
      expect(
        container.read(assistantProvider).layout,
        const FolderLayout(seriesFolders: true),
      );
      expect(assistant.hasConsent, isTrue);
      await assistant.execute();
      expect(organizer.executed, 0);

      await assistant.send('新要求');
      expect(organizer.instructions, ['整理', '新要求']);
      expect(container.read(assistantProvider).planVersion, 1);
    });

    test('处理中或执行中不允许新建会话清空方案', () async {
      final assistant = container.read(assistantProvider.notifier)
        ..grantConsent();
      await assistant.send('整理');
      final conversation = container.read(assistantProvider);
      final plan = container.read(organizerProvider).plan;
      for (final executing in [false, true]) {
        organizer.state = organizer.state.copyWith(
          busy: !executing,
          executing: executing,
        );
        assistant.reset();
        expect(container.read(assistantProvider), same(conversation));
        expect(container.read(organizerProvider).plan, same(plan));
      }
    });

    test('切换目录后清空对话与授权', () async {
      final assistant = container.read(assistantProvider.notifier)
        ..grantConsent();
      await assistant.send('整理');
      expect(container.read(assistantProvider).messages, isNotEmpty);
      organizer.state = organizer.state.copyWith(directory: '/dav/other/');
      expect(container.read(assistantProvider).messages, isEmpty);
      expect(assistant.hasConsent, isFalse);
    });
  });
}
