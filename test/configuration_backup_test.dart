import 'dart:convert';
import 'dart:typed_data';

import 'package:azusa/core/database/app_database.dart';
import 'package:azusa/core/settings/naming_format.dart';
import 'package:azusa/core/settings/naming_language.dart';
import 'package:azusa/core/settings/settings.dart';
import 'package:azusa/features/organizer/connections/configuration_backup.dart';
import 'package:azusa/features/organizer/connections/configuration_transfer.dart';
import 'package:azusa/features/organizer/connections/connection_settings.dart';
import 'package:azusa/features/organizer/connections/file_server_connections.dart';
import 'package:azusa/features/organizer/connections/webdav_connections.dart';
import 'package:azusa/features/organizer/smb/smb_connection.dart';
import 'package:azusa/features/organizer/file_server/file_server_factory.dart';
import 'package:azusa/features/organizer/organizer_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'webdav_connections_test.dart' show MemorySecrets;
import 'webdav_switching_test.dart' show MemoryPreferences, SwitchingOrganizer;

const _passphrase = '  跨设备迁移 passphrase  ';
const _dav = (
  name: '影视 NAS',
  url: 'https://nas.test/dav/',
  username: 'user',
  proxy: true,
  password: 'remote-secret',
);
const _ai = (
  url: 'https://ai.test/v1',
  model: 'new-model',
  proxy: false,
  key: 'incoming-key',
);
const _tmdb = (
  language: NamingLanguage.english,
  format: NamingFormat.dotted,
  proxy: false,
  token: 'incoming-token',
);
const _local = ConnectionSettings(
  model: 'old-model',
  aiKey: 'old-key',
  tmdbToken: 'old-token',
  proxyUrl: 'http://proxy.test:8888',
);

Matcher _problem(BackupProblem value) =>
    throwsA(isA<BackupException>().having((e) => e.problem, 'problem', value));

void main() {
  final codec = ConfigurationBackupCodec();

  test('encrypted backups hide all configuration and authenticate password and contents', () async {
    final backup = ConfigurationBackup(webdav: [_dav], ai: _ai, tmdb: _tmdb);
    final bytes = await codec.encode(backup, passphrase: _passphrase);
    final raw = utf8.decode(bytes);
    expect(codec.isEncrypted(bytes), isTrue);
    for (final value in [
      _dav.name,
      _dav.password,
      _ai.url,
      _ai.key,
      _tmdb.token,
    ]) {
      expect(raw, isNot(contains(value)));
    }
    final result = await codec.decode(bytes, passphrase: _passphrase);
    expect(result.webdav, [_dav]);
    expect(result.ai, _ai);
    expect(result.tmdb, _tmdb);
    await expectLater(
      codec.decode(bytes),
      _problem(BackupProblem.passphraseRequired),
    );
    await expectLater(
      codec.decode(bytes, passphrase: 'wrong passphrase'),
      _problem(BackupProblem.unlockFailed),
    );
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final box = base64Decode(json['box'] as String);
    box[box.length - 1] ^= 1;
    json['box'] = base64Encode(box);
    await expectLater(
      codec.decode(utf8.encode(jsonEncode(json)), passphrase: _passphrase),
      _problem(BackupProblem.unlockFailed),
    );
  });

  test('plaintext format rejects credentials, malformed, unsupported and oversized input', () async {
    await expectLater(
      codec.encode(ConfigurationBackup(ai: _ai)),
      _problem(BackupProblem.invalid),
    );
    await expectLater(
      codec.encode(ConfigurationBackup(ai: _ai), passphrase: 'short'),
      _problem(BackupProblem.passphraseRequired),
    );
    Uint8List file(Object data, {int version = 1}) => utf8.encode(
      jsonEncode({
        'format': 'azusa.configuration',
        'version': version,
        'data': data,
      }),
    );
    await expectLater(
      codec.decode(file({}, version: 3)),
      _problem(BackupProblem.unsupported),
    );
    await expectLater(
      codec.decode(
        file({
          'ai': {
            'url': _ai.url,
            'model': _ai.model,
            'proxy': false,
            'key': 'plaintext',
          },
        }),
      ),
      _problem(BackupProblem.invalid),
    );
    await expectLater(
      codec.decode(
        file({
          'ai': {'url': 'https://secret@ai.test', 'model': '', 'proxy': true},
        }),
      ),
      _problem(BackupProblem.invalid),
    );
    await expectLater(
      codec.decode(
        file({
          'webdav': [
            {
              'name': 'A',
              'url': 'ftp://invalid.test/',
              'username': '',
              'proxy': true,
            },
          ],
        }),
      ),
      _problem(BackupProblem.invalid),
    );
    await expectLater(
      codec.decode(Uint8List(ConfigurationBackupCodec.maxBytes + 1)),
      _problem(BackupProblem.tooLarge),
    );
  });

  group('configuration transfer', () {
    late AppDatabase database;
    late MemoryPreferences prefs;
    late MemorySecrets secrets;
    late ConnectionRepository globals;
    late WebDavConnectionsRepository dav;
    late ProviderContainer container;
    late ConnectionSettingsController controller;

    setUp(() async {
      database = AppDatabase(open: () async => sqlite3.openInMemory());
      prefs = MemoryPreferences();
      secrets = MemorySecrets();
      globals = ConnectionRepository(prefs, secrets);
      dav = WebDavConnectionsRepository(database, secrets);
      await globals.save(_local, includeWebdav: false);
      await dav.initialize(_local);
      await dav.save(
        const WebDavConnection(
          id: 'current',
          name: 'Current',
          url: 'https://NAS.test:443/dav',
          username: 'user',
          password: 'local-password',
        ),
        activate: true,
      );
      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          connectionRepositoryProvider.overrideWithValue(globals),
          preferencesProvider.overrideWithValue(prefs),
          organizerProvider.overrideWith(SwitchingOrganizer.new),
          fileServerClientProvider.overrideWithValue(
            (_) => throw StateError('Import must not access WebDAV'),
          ),
        ],
      );
      await container.read(connectionSettingsProvider.future);
      controller = container.read(connectionSettingsProvider.notifier);
    });

    tearDown(() async {
      container.dispose();
      await database.close();
    });

    test(
      'credential-free round trip is selective and preserves existing secrets',
      () async {
        final sections = BackupSection.values.toSet();
        final exported = await controller.exportConfiguration(
          sections,
          includeCredentials: false,
        );
        final bytes = await codec.encode(exported);
        expect(utf8.decode(bytes), isNot(contains('proxy.test')));
        expect(utf8.decode(bytes), isNot(contains('Current connection')));
        final imported = await codec.decode(bytes);
        expect(imported.sections, sections);
        for (final section in sections) {
          expect(imported.hasCredentials(section), isFalse);
        }
        final preview = await controller.previewConfiguration(imported);
        expect(preview.additions, isEmpty);
        expect(preview.skipped, 1);
        await controller.importConfiguration(preview, sections);
        expect((await globals.load()).aiKey, _local.aiKey);
        expect((await globals.load()).tmdbToken, _local.tmdbToken);
        expect((await dav.load()).single.password, 'local-password');
        expect(await dav.activeId(), 'current');
        expect(container.read(organizerProvider).plan, isNotEmpty);
      },
    );

    test('encrypted values go to the vault, duplicates are skipped and active ID is preserved', () async {
      final other = (
        name: 'Other',
        url: _dav.url,
        username: 'another-user',
        proxy: true,
        password: _dav.password,
      );
      final backup = ConfigurationBackup(
        webdav: [_dav, other, other],
        ai: _ai,
        tmdb: _tmdb,
      );
      expect(
        await container.read(webDavConnectionsProvider.future),
        hasLength(1),
      );
      final preview = await controller.previewConfiguration(backup);
      expect(preview.additions, [other]);
      expect(preview.skipped, 2);
      await controller.importConfiguration(preview, backup.sections);
      expect(
        await container.read(webDavConnectionsProvider.future),
        hasLength(2),
      );
      expect(await dav.activeId(), 'current');
      expect((await dav.load()).map((d) => d.password), [
        'local-password',
        _dav.password,
      ]);
      final saved = await globals.load(includeWebdav: false);
      expect(saved.aiKey, _ai.key);
      expect(saved.tmdbToken, _tmdb.token);
      expect(saved.proxyUrl, _local.proxyUrl);
      expect(container.read(settingsProvider).namingFormat, _tmdb.format);
      expect(prefs.values.values.join(), isNot(contains(_tmdb.token)));
      expect((await controller.previewConfiguration(backup)).skipped, 3);
    });

    test(
      'SMB and WebDAV import together and keep the active connection',
      () async {
        const smb = (
          name: 'Media',
          host: 'nas.local',
          share: 'Movies',
          domain: 'WORKGROUP',
          username: 'media',
          password: 'smb-password',
        );
        final backup = ConfigurationBackup(
          smb: [smb],
          webdav: [
            (
              name: 'Second DAV',
              url: 'https://nas.test/second/',
              username: 'other',
              proxy: false,
              password: null,
            ),
          ],
        );
        final preview = await controller.previewConfiguration(backup);
        expect(preview.smbAdditions, [smb]);
        await controller.importConfiguration(preview, backup.sections);
        expect((await dav.load()).length, 2);
        expect(await dav.activeId(), 'current');
        final repository = container.read(
          fileServerConnectionsRepositoryProvider,
        );
        final stored = (await repository.load())
            .whereType<SmbConnection>()
            .single;
        expect(stored.password, smb.password);
        expect((await repository.active())?.id, 'current');
        expect((await controller.previewConfiguration(backup)).smbSkipped, 1);
        final exported = await controller.exportConfiguration({
          BackupSection.smb,
        }, includeCredentials: false);
        expect(exported.webdav, isNull);
        expect(exported.smb!.single.password, isNull);
        expect(exported.smb!.single.domain, smb.domain);
      },
    );

    test('AI address changes require an explicit new key; busy state blocks import', () async {
      final backup = ConfigurationBackup(
        ai: (url: _ai.url, key: null, model: _ai.model, proxy: _ai.proxy),
        tmdb: _tmdb,
      );
      final preview = await controller.previewConfiguration(backup);
      expect(preview.aiNeedsKey, isTrue);
      await expectLater(
        controller.importConfiguration(preview, {BackupSection.ai}),
        throwsA(isA<ConfigurationImportChanged>()),
      );
      expect((await globals.load()).aiUrl, _local.aiUrl);
      await controller.importConfiguration(preview, {BackupSection.tmdb});
      await controller.importConfiguration(preview, {
        BackupSection.ai,
      }, replacementAiKey: 'replacement');
      expect((await globals.load()).aiKey, 'replacement');
      (container.read(organizerProvider.notifier) as SwitchingOrganizer).lock();
      await expectLater(
        controller.importConfiguration(preview, {BackupSection.tmdb}),
        throwsStateError,
      );
    });

    test('database failure rolls back all sections and leaves no staged credentials', () async {
      final before = Map.of(secrets.values);
      final db = await database.connection();
      db.execute(
        "CREATE TRIGGER reject_import BEFORE INSERT ON webdav_connections BEGIN SELECT RAISE(ABORT, 'failure'); END",
      );
      final backup = ConfigurationBackup(
        webdav: [
          (
            name: 'Other',
            url: 'https://other.test/',
            username: '',
            proxy: false,
            password: 'new-password',
          ),
        ],
        ai: _ai,
        tmdb: _tmdb,
      );
      final preview = await controller.previewConfiguration(backup);
      await expectLater(
        controller.importConfiguration(preview, backup.sections),
        throwsA(isA<SqliteException>()),
      );
      expect(secrets.values, before);
      expect((await globals.load()).aiUrl, _local.aiUrl);
      expect(
        container.read(settingsProvider).namingFormat,
        NamingFormat.standard,
      );
      expect((await dav.load()).single.id, 'current');
      expect(container.read(organizerProvider).busy, isFalse);
    });
  });
}
