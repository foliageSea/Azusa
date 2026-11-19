import 'dart:convert';
import 'dart:io';

import 'package:azusa/core/database/app_database.dart';
import 'package:azusa/features/organizer/connections/connection_settings.dart';
import 'package:azusa/features/organizer/connections/credential_vault.dart';
import 'package:azusa/features/organizer/connections/file_server_connections.dart';
import 'package:azusa/features/organizer/connections/webdav_connections.dart';
import 'package:azusa/features/organizer/smb/smb_connection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'webdav_connections_test.dart' show MemorySecrets;

const _webDav = WebDavConnection(
  id: 'dav',
  name: 'WebDAV NAS',
  url: 'https://nas.test/dav/',
  username: 'dav-user',
  password: 'dav-secret',
  useProxy: true,
);
const _smb = SmbConnection(
  id: 'smb',
  name: 'SMB NAS',
  host: 'nas.test',
  share: 'Media',
  domain: 'HOME',
  username: 'smb-user',
  password: 'smb-secret',
);

class _Settings extends ConnectionSettingsController {
  @override
  Future<ConnectionSettings> build() async => const ConnectionSettings();
}

String? _vault(MemorySecrets secrets) =>
    secrets.values[CredentialVault.storageKey];

void main() {
  late AppDatabase database;
  late MemorySecrets secrets;
  late WebDavConnectionsRepository legacy;
  late FileServerConnectionsRepository repository;

  setUp(() {
    database = AppDatabase(open: () async => sqlite3.openInMemory());
    secrets = MemorySecrets();
    legacy = WebDavConnectionsRepository(database, secrets);
    repository = FileServerConnectionsRepository.fromWebDav(legacy);
  });
  tearDown(() => database.close());

  test('mixed activation is synchronized with the legacy WebDAV API', () async {
    await repository.save(_smb);
    expect(await repository.active(), isNull);
    await legacy.save(_webDav, activate: true);
    expect(
      (await repository.active() as WebDavConnection).password,
      _webDav.password,
    );

    await repository.select(_smb.id);
    expect(await legacy.activeId(), isNull);
    final active = await repository.active() as SmbConnection;
    expect(
      [
        active.host,
        active.share,
        active.domain,
        active.username,
        active.password,
      ],
      [_smb.host, _smb.share, _smb.domain, _smb.username, _smb.password],
    );
    await legacy.select(null);
    await legacy.remove(_webDav.id);
    expect((await repository.active())?.id, _smb.id);

    await repository.save(_webDav);
    await legacy.select(_webDav.id);
    expect((await repository.active())?.id, _webDav.id);
    await legacy.remove(_webDav.id);
    expect(await repository.active(), isNull);

    await repository.select(_smb.id);
    await repository.remove(_smb.id);
    expect(await repository.active(), isNull);
    expect(await repository.load(), isEmpty);
    expect(jsonDecode(_vault(secrets)!)['values'], isEmpty);
    await expectLater(repository.select('missing'), throwsStateError);
    await expectLater(repository.withPassword(_smb), throwsStateError);
  });

  test(
    'redacted provider uses injected WebDAV storage without opening the vault',
    () async {
      final db = await database.connection();
      db.execute(
        "INSERT INTO webdav_connections VALUES ('dav', 'NAS', 'https://nas.test/', '', 0, 'key-dav')",
      );
      db.execute(
        "INSERT INTO smb_connections VALUES ('smb', 'NAS', 'nas.test', 'Media', '', 'user', 'key-smb')",
      );
      final container = ProviderContainer(
        overrides: [
          connectionSettingsProvider.overrideWith(_Settings.new),
          webDavConnectionsRepositoryProvider.overrideWithValue(legacy),
        ],
      );
      addTearDown(container.dispose);
      expect(
        container.read(fileServerConnectionsRepositoryProvider).database,
        same(database),
      );
      final values = await container.read(fileServerConnectionsProvider.future);
      expect(values.map((value) => value.protocol), ['webdav', 'smb']);
      expect((values.first as WebDavConnection).password, isEmpty);
      expect((values.last as SmbConnection).password, isEmpty);
      expect(secrets.reads, isEmpty);
      expect(secrets.writes, isEmpty);
    },
  );

  test(
    'mixed imports stage references in the vault and never activate a server',
    () async {
      await repository.insertImported([_webDav, _smb]);
      expect(await repository.active(), isNull);
      final db = await database.connection();
      final davRow = db.select('SELECT * FROM webdav_connections').single;
      final smbRow = db.select('SELECT * FROM smb_connections').single;
      expect(davRow.values, isNot(contains(_webDav.password)));
      expect(smbRow.values, isNot(contains(_smb.password)));
      expect(jsonDecode(_vault(secrets)!)['values'], {
        davRow['secret_key']: _webDav.password,
        smbRow['secret_key']: _smb.password,
      });
      final redacted = await repository.load(includePasswords: false);
      expect(
        (await repository.withPassword(
          redacted.first,
        ) as WebDavConnection).password,
        _webDav.password,
      );
      expect(
        (await repository.withPassword(
          redacted.last,
        ) as SmbConnection).password,
        _smb.password,
      );
      final full = await repository.load();
      expect((full.first as WebDavConnection).useProxy, isTrue);
      expect((full.last as SmbConnection).password, _smb.password);
    },
  );

  test(
    'mixed import failure rolls back both tables and staged credentials',
    () async {
      const original = WebDavConnection(
        id: 'original',
        name: 'Original',
        url: 'https://original.test/',
        password: 'original-secret',
      );
      await legacy.save(original, activate: true);
      final oldVault = _vault(secrets);
      final db = await database.connection();
      db.execute(
        "CREATE TRIGGER reject_smb BEFORE INSERT ON smb_connections BEGIN SELECT RAISE(ROLLBACK, 'import failure'); END",
      );
      await expectLater(
        repository.insertImported([_webDav, _smb]),
        throwsA(
          isA<SqliteException>().having(
            (error) => error.message,
            'message',
            'import failure',
          ),
        ),
      );
      expect((await repository.active())?.id, original.id);
      expect((await repository.load()).map((value) => value.id), [original.id]);
      expect(_vault(secrets), oldVault);

      db.execute('DROP TRIGGER reject_smb');
      secrets.failWrite = true;
      await expectLater(
        repository.insertImported([_webDav, _smb]),
        throwsStateError,
      );
      expect((await repository.load()).map((value) => value.id), [original.id]);
      expect(_vault(secrets), oldVault);
    },
  );

  test(
    'SMB save keeps the old credential if the database write fails',
    () async {
      await repository.save(_smb);
      await repository.select(_smb.id);
      final oldVault = _vault(secrets);
      final db = await database.connection();
      db.execute(
        "CREATE TRIGGER reject_smb BEFORE UPDATE ON smb_connections BEGIN SELECT RAISE(ABORT, 'failure'); END",
      );
      const changed = SmbConnection(
        id: 'smb',
        name: 'Changed',
        host: 'nas.test',
        share: 'Media',
        username: 'smb-user',
        password: 'new-secret',
      );
      await expectLater(
        repository.save(changed),
        throwsA(isA<SqliteException>()),
      );
      expect(
        (await repository.active() as SmbConnection).password,
        _smb.password,
      );
      expect(_vault(secrets), oldVault);
      db.execute('DROP TRIGGER reject_smb');
      await repository.save(changed);
      expect(
        (await repository.active() as SmbConnection).password,
        changed.password,
      );
      expect((jsonDecode(_vault(secrets)!)['values'] as Map).values, [
        changed.password,
      ]);
    },
  );

  test('bare ids cannot collide across protocols', () async {
    await repository.save(_webDav);
    const collision = SmbConnection(
      id: 'dav',
      name: 'SMB',
      host: 'nas.test',
      share: 'Media',
      username: 'user',
      password: 'collision-secret',
    );
    final oldVault = _vault(secrets);
    await expectLater(
      repository.save(collision),
      throwsA(isA<SqliteException>()),
    );
    expect(_vault(secrets), oldVault);
    expect((await repository.load()).single, isA<WebDavConnection>());
  });

  test('SMB remains active across database and vault reopen', () async {
    final directory = await Directory.systemTemp.createTemp('azusa-db-v3-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/azusa.sqlite3';
    final first = AppDatabase(open: () async => sqlite3.open(path));
    addTearDown(first.close);
    final stored = FileServerConnectionsRepository(first, secrets);
    await stored.insertImported([_webDav, _smb]);
    await stored.select(_webDav.id);
    await stored.select(_smb.id);
    await first.close();

    final reopened = AppDatabase(open: () async => sqlite3.open(path));
    addTearDown(reopened.close);
    final reopenedSecrets = MemorySecrets()..values.addAll(secrets.values);
    final persisted = FileServerConnectionsRepository(
      reopened,
      reopenedSecrets,
    );
    expect((await persisted.active() as SmbConnection).password, _smb.password);
    expect(await persisted.load(includePasswords: false), hasLength(2));
  });
}
