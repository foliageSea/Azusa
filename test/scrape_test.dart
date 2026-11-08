import 'dart:convert';

import 'package:azusa/core/database/app_database.dart';
import 'package:azusa/features/organizer/ai/tmdb.dart';
import 'package:azusa/features/organizer/history/execution_history.dart';
import 'package:azusa/features/organizer/organizer_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:azusa/features/organizer/connections/connection_settings.dart';
import 'package:azusa/features/organizer/dav/webdav.dart';
import 'package:azusa/features/organizer/scrape/media_identity.dart';
import 'package:azusa/features/organizer/scrape/nfo.dart';
import 'package:azusa/features/organizer/scrape/scrape_cleaner.dart';
import 'package:azusa/features/organizer/scrape/scraper.dart';
import 'package:azusa/l10n/generated/app_localizations_en.dart';
import 'package:azusa/shared/runtime_localization.dart';
import 'package:flutter_test/flutter_test.dart';

const _settings = ConnectionSettings(
  webdavUrl: 'https://nas.test/dav/',
  tmdbToken: 'token',
);

String _p(String path) =>
    path.split('/').map((s) => Uri.encodeComponent(s)).join('/');

class _Dav extends WebDavClient {
  _Dav(Iterable<String> paths) : super(_settings) {
    for (final path in paths) {
      add(path);
    }
  }
  final files = <String, DavEntry>{};
  final uploads = <String, List<int>>{};
  final deleted = <String>[];

  void add(String raw, {String? etag}) {
    final path = _p(raw);
    files[path] = DavEntry(path, path.endsWith('/'), etag: etag ?? 'e');
    var parent = path.substring(0, path.lastIndexOf('/', path.length - 2) + 1);
    while (parent.length > '/dav/'.length) {
      files.putIfAbsent(parent, () => DavEntry(parent, true));
      parent = parent.substring(
        0,
        parent.lastIndexOf('/', parent.length - 2) + 1,
      );
    }
  }

  @override
  Future<List<DavEntry>> listAll(String path) async => [
    for (final e in files.values)
      if (e.path != path &&
          e.path.startsWith(path) &&
          !e.path
              .substring(path.length)
              .replaceFirst(RegExp(r'/$'), '')
              .contains('/'))
        e,
  ];

  @override
  Future<List<DavEntry>> list(String path) async => [
    for (final e in await listAll(path))
      if (!e.name.startsWith('.')) e,
  ];

  @override
  Future<DavEntry?> stat(String path) async => files[path];

  @override
  Future<void> upload(String path, Stream<List<int>> bytes, int length) async {
    if (files.containsKey(path)) throw StateError('exists');
    final data = [for (final chunk in await bytes.toList()) ...chunk];
    expect(data.length, length);
    uploads[path] = data;
    files[path] = DavEntry(path, false, etag: 'new');
  }

  @override
  Future<void> remove(String path) async {
    deleted.add(path);
    files.remove(path);
  }
}

class _Tmdb extends TmdbClient {
  _Tmdb() : super(_settings);
  final searches = <String>[];

  @override
  Future<List<Map<String, dynamic>>> searchMovies(
    String query, {
    int? year,
  }) async {
    searches.add('movie:$query:$year');
    if (query == 'Interstellar') {
      return [
        {'id': 1, 'title': 'Interstellar Remake', 'release_date': '2030-01-01'},
        {'id': 157336, 'title': '星际穿越', 'release_date': '2014-11-05'},
      ];
    }
    return [];
  }

  @override
  Future<List<Map<String, dynamic>>> search(String query) async {
    searches.add('tv:$query');
    if (query == '绝命毒师') {
      return [
        {'id': 1396, 'name': '绝命毒师', 'first_air_date': '2008-01-20'},
      ];
    }
    return [];
  }

  @override
  Future<Map<String, dynamic>> movieMetadata(int id) async => {
    'id': id,
    'title': '星际穿越',
    'original_title': 'Interstellar',
    'release_date': '2014-11-05',
    'overview': 'A <team> & explorers',
    'poster_path': '/poster.jpg',
    'backdrop_path': '/backdrop.jpg',
    'genres': [
      {'name': '科幻'},
    ],
    'credits': {
      'cast': [
        {'name': 'Matthew', 'character': 'Cooper', 'profile_path': '/m.jpg'},
      ],
      'crew': [
        {'name': 'Nolan', 'job': 'Director'},
      ],
    },
  };

  @override
  Future<Map<String, dynamic>> tvMetadata(int id) async => {
    'id': id,
    'name': '绝命毒师',
    'first_air_date': '2008-01-20',
    'poster_path': '/show.jpg',
    'backdrop_path': null,
    'external_ids': {'imdb_id': 'tt0903747', 'tvdb_id': 81189},
  };

  @override
  Future<Map<String, dynamic>> seasonMetadata(int id, int number) async => {
    'poster_path': '/season.png',
    'episodes': [
      {
        'id': 62085,
        'episode_number': 1,
        'name': '试播集',
        'air_date': '2008-01-20',
        'still_path': '/still.jpg',
      },
    ],
  };

  @override
  Future<List<int>> image(String path, {String size = 'original'}) async =>
      utf8.encode('$size$path');
}

class _Connections extends ConnectionSettingsController {
  @override
  Future<ConnectionSettings> build() async => _settings;
}

void main() {
  group('guessMedia', () {
    test('parses organizer movie and episode names', () {
      final movie = guessMedia(_p('/dav/电影/星际穿越 (2014).mkv'))!;
      expect(movie.kind, ScrapeMediaKind.movie);
      expect(movie.title, '星际穿越');
      expect(movie.year, 2014);

      final dotted = guessMedia(_p('/dav/Interstellar.2014.1080p.BluRay.mkv'))!;
      expect((dotted.title, dotted.year), ('Interstellar', 2014));

      final episode = guessMedia(
        _p('/dav/绝命毒师 (2008)/Season 1/绝命毒师 - S01E02 - 猫在袋子里.mkv'),
      )!;
      expect(episode.kind, ScrapeMediaKind.episode);
      expect(episode.title, '绝命毒师');
      expect(episode.year, 2008);
      expect((episode.season, episode.episode), (1, 2));
    });

    test('falls back to folders and reads TMDB id hints', () {
      final episode = guessMedia(_p('/dav/Breaking Bad/S02/S02E03.mkv'))!;
      expect(episode.title, 'Breaking Bad');
      expect(episode.season, 2);

      final movie = guessMedia(_p('/dav/Heat (1995) [tmdbid=949]/movie.mkv'))!;
      expect((movie.title, movie.year, movie.tmdbId), ('Heat', 1995, 949));

      expect(guessMedia(_p('/dav/2012.mkv'))!.title, '2012');
      expect(guessMedia(_p('/dav/Movie (2010)/Movie-trailer.mkv')), isNull);
    });

    test('show root skips season folders', () {
      expect(showRootFor('/dav/A/Season%201/x.mkv'), '/dav/A/');
      expect(showRootFor('/dav/A/x.mkv'), '/dav/A/');
    });
  });

  test('NFO documents escape TMDB text', () async {
    final xml = movieNfo(await _Tmdb().movieMetadata(157336));
    expect(xml, contains('<title>星际穿越</title>'));
    expect(xml, contains('A &lt;team> &amp; explorers'));
    expect(
      xml,
      contains('<uniqueid type="tmdb" default="true">157336</uniqueid>'),
    );
    expect(xml, contains('<director>Nolan</director>'));
    expect(xml, contains('https://image.tmdb.org/t/p/w185/m.jpg'));
    final episode = episodeNfo({'name': 'Show'}, null, season: 1, number: 3);
    expect(episode, contains('<episode>3</episode>'));
  });

  test('scrape scans, matches TMDB and writes without overwriting', () async {
    final dav = _Dav([
      '/dav/lib/Interstellar (2014)/Interstellar (2014).mkv',
      '/dav/lib/Interstellar (2014)/Interstellar (2014)-poster.jpg',
      '/dav/lib/绝命毒师/Season 1/绝命毒师 - S01E01 - 试播集.mkv',
      '/dav/lib/Unknown thing.mkv',
    ]);
    addTearDown(dav.close);
    final tmdb = _Tmdb();
    final scraper = MetadataScraper(dav, tmdb);
    final scan = await scraper.scan('/dav/lib/');
    expect(scan.unmatched, [_p('/dav/lib/Unknown thing.mkv')]);
    expect(
      scan.targets.map((t) => (t.tmdbId, t.title)),
      unorderedEquals([(157336, '星际穿越'), (1396, '绝命毒师')]),
    );
    expect(tmdb.searches, contains('movie:Interstellar:2014'));

    final result = await scraper.write('/dav/lib/', scan.targets, scan.targets);
    expect(result, (written: 7, skipped: 1));
    final written = dav.uploads.keys.map(Uri.decodeComponent).toSet();
    expect(written, {
      '/dav/lib/Interstellar (2014)/Interstellar (2014).nfo',
      '/dav/lib/Interstellar (2014)/Interstellar (2014)-fanart.jpg',
      '/dav/lib/绝命毒师/tvshow.nfo',
      '/dav/lib/绝命毒师/poster.jpg',
      '/dav/lib/绝命毒师/season01-poster.png',
      '/dav/lib/绝命毒师/Season 1/绝命毒师 - S01E01 - 试播集.nfo',
      '/dav/lib/绝命毒师/Season 1/绝命毒师 - S01E01 - 试播集-thumb.jpg',
    });
    expect(
      utf8.decode(
        dav.uploads[_p(
          '/dav/lib/Interstellar (2014)/Interstellar (2014)-fanart.jpg',
        )]!,
      ),
      'w1280/backdrop.jpg',
    );
    expect(
      utf8.decode(dav.uploads[_p('/dav/lib/绝命毒师/tvshow.nfo')]!),
      contains('<uniqueid type="tvdb">81189</uniqueid>'),
    );

    final again = await MetadataScraper(
      dav,
      tmdb,
    ).write('/dav/lib/', scan.targets, scan.targets);
    expect(again.written, 0);
  });

  test('show-level files are skipped for mixed folders', () {
    const episode = ScrapeTarget(
      video: '/dav/tv/a.S01E01.mkv',
      kind: ScrapeMediaKind.episode,
      tmdbId: 1,
      title: 'A',
      season: 1,
      episode: 1,
    );
    const other = ScrapeTarget(
      video: '/dav/tv/b.S01E01.mkv',
      kind: ScrapeMediaKind.episode,
      tmdbId: 2,
      title: 'B',
      season: 1,
      episode: 1,
    );
    expect(MetadataScraper.showRoots([episode]), {'/dav/tv/': 1});
    expect(MetadataScraper.showRoots([episode, other]), isEmpty);
  });

  test(
    'scrape cleanup finds scraper output only and re-checks files',
    () async {
      final dav = _Dav([
        '/dav/m/Movie (2014).mkv',
        '/dav/m/Movie (2014).nfo',
        '/dav/m/Movie (2014)-poster.jpg',
        '/dav/m/Movie (2014)-fanart.jpg',
        '/dav/m/poster.jpg',
        '/dav/m/season01-poster.jpg',
        '/dav/m/holiday.jpg',
        '/dav/m/Other-poster.jpg',
        '/dav/m/extrafanart/1.jpg',
        '/dav/m/.actors/Actor.jpg',
        '/dav/m/.hidden/poster.jpg',
        '/dav/m/sub/tvshow.nfo',
      ]);
      addTearDown(dav.close);
      final cleaner = ScrapeCleaner(dav);
      final artifacts = await cleaner.scan('/dav/m/');
      expect(artifacts.map((a) => Uri.decodeComponent(a.path)).toSet(), {
        '/dav/m/Movie (2014).nfo',
        '/dav/m/Movie (2014)-poster.jpg',
        '/dav/m/Movie (2014)-fanart.jpg',
        '/dav/m/poster.jpg',
        '/dav/m/season01-poster.jpg',
        '/dav/m/extrafanart/1.jpg',
        '/dav/m/.actors/Actor.jpg',
        '/dav/m/sub/tvshow.nfo',
      });

      // A file changed after scanning is skipped rather than deleted.
      dav.add('/dav/m/poster.jpg', etag: 'changed');
      final result = await cleaner.clean('/dav/m/', artifacts);
      expect(result, (deleted: 7, skipped: 1));
      expect(dav.files.containsKey(_p('/dav/m/holiday.jpg')), isTrue);
      expect(dav.files.containsKey(_p('/dav/m/Movie (2014).mkv')), isTrue);

      await expectLater(
        cleaner.clean('/dav/m/sub/', [
          ScrapeArtifact(_p('/dav/m/holiday.jpg'), ScrapeArtifactKind.image),
        ]),
        throwsStateError,
      );
    },
  );

  test('controller scrapes and cleans only scanned candidates', () async {
    final db = AppDatabase(open: () async => sqlite3.openInMemory());
    addTearDown(db.close);
    final dav = _Dav(['/dav/Interstellar (2014).mkv', '/dav/notes.nfo']);
    final history = ExecutionHistoryRepository(db);
    final container = ProviderContainer(
      overrides: [
        connectionSettingsProvider.overrideWith(_Connections.new),
        webDavFactoryProvider.overrideWithValue((_) => dav),
        tmdbFactoryProvider.overrideWithValue((_) => _Tmdb()),
        executionHistoryRepositoryProvider.overrideWithValue(history),
      ],
    );
    addTearDown(container.dispose);
    await container.read(connectionSettingsProvider.future);
    final controller = container.read(organizerProvider.notifier);
    await controller.open('/dav/');

    // Writing requires a prior scan in the same scope.
    await controller.executeScrape([_p('/dav/Interstellar (2014).mkv')]);
    expect(dav.uploads, isEmpty);

    final scan = (await controller.scanScrapeTargets())!;
    expect(scan.targets.single.tmdbId, 157336);
    await controller.executeScrape([scan.targets.single.video], artwork: false);
    expect(
      container.read(organizerProvider).message,
      '搜刮完成：已写入 1 个文件，跳过 0 个已存在文件',
    );
    expect(dav.uploads.keys.map(Uri.decodeComponent), [
      '/dav/Interstellar (2014).nfo',
    ]);
    expect((await history.load()).where((e) => e.contains('upload')).length, 2);

    final artifacts = await controller.scanScrapeArtifacts();
    expect(artifacts.length, 2);
    await controller.cleanScrapeArtifacts([_p('/dav/other.nfo')]);
    expect(dav.deleted, isEmpty);
    await controller.cleanScrapeArtifacts([_p('/dav/Interstellar (2014).nfo')]);
    expect(dav.deleted.map(Uri.decodeComponent), [
      '/dav/Interstellar (2014).nfo',
    ]);
    expect(dav.files.containsKey(_p('/dav/notes.nfo')), isTrue);
    expect(
      container.read(organizerProvider).message,
      '清理完成：已删除 1 个搜刮文件，跳过 0 个文件',
    );
  });

  test('scrape messages are localized', () {
    final l = AppLocalizationsEn();
    expect(
      localizeRuntimeMessage(l, '搜刮完成：已写入 3 个文件，跳过 1 个已存在文件'),
      'Scraping complete: wrote 3 files, skipped 1 existing files',
    );
    expect(
      localizeRuntimeMessage(l, '清理已停止：已删除 1 个搜刮文件，跳过 0 个文件；清理已中止'),
      'Cleanup stopped: deleted 1 scraped files, skipped 0 files; Cleanup cancelled',
    );
  });
}
