import 'dart:async';
import 'dart:io';

import 'package:azusa/features/organizer/ai/tmdb.dart';
import 'package:azusa/features/organizer/connections/connection_settings.dart';
import 'package:azusa/features/organizer/dav/directory_scan.dart';
import 'package:azusa/features/organizer/file_server/file_server.dart';
import 'package:azusa/features/organizer/file_server/file_server_factory.dart';
import 'package:azusa/features/organizer/file_server/file_server_paths.dart';
import 'package:azusa/features/organizer/rename_plan.dart';
import 'package:azusa/features/organizer/scrape/media_identity.dart';
import 'package:azusa/features/organizer/scrape/scrape_cleaner.dart';
import 'package:azusa/features/organizer/scrape/scraper.dart';
import 'package:azusa/features/organizer/smb/smb_connection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const password = 'azusa-integration-only';
  final enabled = Platform.environment['AZU_SMB_INTEGRATION'] == '1';
  FileServerClient client({String share = 'media', String secret = password}) =>
      defaultFileServerFactory.create(
        ConnectionSettings(
          fileServerConnection: SmbConnection(
            id: 'integration',
            name: 'Samba test',
            host: '127.0.0.1',
            share: share,
            username: 'azusa',
            password: secret,
          ),
        ),
      );
  const skipServer =
      'Start the loopback Samba fixture and set AZU_SMB_INTEGRATION=1.';

  test('signed Samba connection, pagination and permissions', () async {
    final server = client(),
        invalid = client(secret: 'intentionally-wrong'),
        readOnly = client(share: 'readonly'),
        missing = client(share: 'not-a-share');
    addTearDown(() {
      for (final item in [server, invalid, readOnly, missing]) {
        item.close();
      }
    });
    expect(await server.listAll('/pagination/'), hasLength(1400));
    expect(await server.stat('/not-an-entry'), isNull);
    await expectLater(invalid.list('/'), throwsStateError);
    await expectLater(missing.stat('/not-an-entry'), throwsStateError);
    expect(await readOnly.list('/'), isNotEmpty);
    await expectLater(readOnly.mkdir('/forbidden/'), throwsStateError);
  }, skip: enabled ? false : skipServer);

  test(
    'Samba streaming, concurrent collision, organizer, scraper and cleanup',
    () async {
      final server = client(), peer = client();
      addTearDown(server.close);
      addTearDown(peer.close);
      final local = await Directory.systemTemp.createTemp('azusa-smb-');
      addTearDown(() => local.delete(recursive: true));
      final root = '/workflow-${DateTime.now().microsecondsSinceEpoch}/';
      await server.mkdir(root);
      final source = childFileServerPath(root, '星际 % 1.mkv');
      final bytes = List.generate(2 * 1024 * 1024 + 3, (i) => i % 251);
      const chunk = 60023;
      Stream<List<int>> uploadStream() async* {
        for (var i = 0; i < bytes.length; i += chunk) {
          yield bytes.sublist(
            i,
            i + chunk > bytes.length ? bytes.length : i + chunk,
          );
        }
      }

      await server.upload(source, uploadStream(), bytes.length);
      final discovered = (await scanMediaDirectories(
        server,
        root,
        recursive: true,
      )).single;
      expect(discovered.name, '星际 % 1.mkv');
      expect(discovered.size, bytes.length);
      final file = File('${local.path}/download.mkv');
      await server.download(source, file.path);
      expect(await file.readAsBytes(), bytes);
      await expectLater(server.remove(root), throwsStateError);

      final staged = Completer<void>(), publish = Completer<void>();
      final collision = '${root}collision.bin';
      final slowUpload = server.upload(
        collision,
        (() async* {
          yield [1];
          staged.complete();
          await publish.future;
          yield [2];
        })(),
        2,
      );
      final rejected = expectLater(slowUpload, throwsStateError);
      try {
        await Future.any([staged.future, slowUpload]);
        await peer.upload(collision, Stream.value([3, 4, 5]), 3);
      } finally {
        publish.complete();
      }
      await rejected;
      await server.download(collision, file.path);
      expect(await file.readAsBytes(), [3, 4, 5]);
      await server.remove(collision);

      final folder = childFileServerPath(root, '星际穿越 (2014)', directory: true);
      final item = RenameItem(
        source: source,
        targetName: '星际穿越 (2014).mkv',
        targetDirectory: folder,
        scope: root,
        fingerprint: discovered.fingerprint,
      );
      final result = await RenameExecutor(server).execute([item]);
      expect(result.error, isNull);
      expect(await server.stat(source), isNull);
      expect((await server.stat(item.target))?.size, bytes.length);
      final tmdb = _Tmdb();
      addTearDown(() => tmdb.dio.close(force: true));
      final media = ScrapeTarget(
        video: item.target,
        kind: ScrapeMediaKind.movie,
        tmdbId: 157336,
        title: '星际穿越',
        year: 2014,
      );
      final metadata = MetadataScraper(server, tmdb);
      expect(await metadata.write(root, [media], [media], artwork: false), (
        written: 1,
        skipped: 0,
      ));
      expect(await metadata.write(root, [media], [media], artwork: false), (
        written: 0,
        skipped: 1,
      ));
      final cleanup = ScrapeCleaner(server);
      final items = await cleanup.scan(root);
      expect(items.single.path, endsWith('.nfo'));
      expect(await cleanup.clean(root, items), (deleted: 1, skipped: 0));
      await server.remove(item.target);
      final empty = EmptyDirectoryCleaner(server);
      expect(await empty.scan(root), [folder]);
      expect(await empty.clean(root, [folder]), (deleted: 1, skipped: 0));
      await server.remove(root);
    },
    skip: enabled ? false : skipServer,
  );
}

class _Tmdb extends TmdbClient {
  _Tmdb() : super(const ConnectionSettings());

  @override
  Future<Map<String, dynamic>> movieMetadata(int id) async => {
    'id': id,
    'title': '星际穿越',
    'original_title': 'Interstellar',
    'release_date': '2014-11-05',
  };
}
