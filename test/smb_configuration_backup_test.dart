import 'dart:convert';
import 'dart:typed_data';

import 'package:azusa/features/organizer/connections/configuration_backup.dart';
import 'package:azusa/features/organizer/connections/configuration_transfer.dart';
import 'package:azusa/features/organizer/connections/connection_settings.dart';
import 'package:azusa/features/organizer/connections/webdav_connections.dart';
import 'package:azusa/features/organizer/smb/smb_connection.dart';
import 'package:flutter_test/flutter_test.dart';

const BackupDav _dav = (
  name: 'WebDAV library',
  url: 'https://nas.test/dav/',
  username: 'reader',
  proxy: false,
  password: null,
);
const BackupSmb _smb = (
  name: 'SMB library',
  host: 'nas.test',
  share: 'Movie Library',
  domain: 'OFFICE',
  username: 'reader',
  password: null,
);
const _smbJson = {
  'name': 'SMB library',
  'host': 'nas.test',
  'share': 'Movie Library',
  'domain': 'OFFICE',
  'username': 'reader',
};
const _secret = 'unique SMB password';
const _passphrase = 'backup passphrase';

BackupSmb _smbWith({String? share, String? domain, String? password}) => (
  name: _smb.name,
  host: _smb.host,
  share: share ?? _smb.share,
  domain: domain ?? _smb.domain,
  username: _smb.username,
  password: password,
);

Map<String, dynamic> _json(Uint8List bytes) =>
    jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

Uint8List _plaintext(Object data, {int version = 2}) => utf8.encode(
  jsonEncode({
    'format': 'azusa.configuration',
    'version': version,
    'data': data,
  }),
);

Matcher _problem(BackupProblem value) =>
    throwsA(isA<BackupException>().having((e) => e.problem, 'problem', value));

void main() {
  final codec = ConfigurationBackupCodec();

  test('exports v1 without SMB and v2 with an SMB section', () async {
    final legacy = await codec.encode(ConfigurationBackup(webdav: [_dav]));
    expect(_json(legacy)['version'], 1);
    final decodedLegacy = await codec.decode(legacy);
    expect(decodedLegacy.webdav, [_dav]);
    expect(decodedLegacy.smb, isNull);

    final bytes = await codec.encode(
      ConfigurationBackup(webdav: [_dav], smb: [_smb]),
    );
    expect(_json(bytes)['version'], 2);
    expect((_json(bytes)['data'] as Map)['smb'], [_smbJson]);
    expect(codec.isEncrypted(bytes), isFalse);
    final decoded = await codec.decode(bytes);
    expect(decoded.sections, {BackupSection.webdav, BackupSection.smb});
    expect(decoded.webdav, [_dav]);
    expect(decoded.smb, [_smb]);
    expect(decoded.hasCredentials(BackupSection.smb), isFalse);

    final empty = await codec.encode(ConfigurationBackup(smb: []));
    expect(_json(empty)['version'], 2);
    expect((await codec.decode(empty)).smb, isEmpty);
  });

  test(
    'strict SMB schema rejects v1 data and invalid or secret fields',
    () async {
      await expectLater(
        codec.decode(
          _plaintext({
            'smb': [_smbJson],
          }, version: 1),
        ),
        _problem(BackupProblem.invalid),
      );
      for (final field in [
        {'id': 'not backed up'},
        {'password': _secret},
        {'password': null},
        {'name': ''},
        {'host': 'smb://someone:password@nas.test'},
        {'share': 'Movies/Series'},
        {'share': ' Movies '},
        {'domain': 'OFFICE\\reader'},
        {'username': 'reader\n'},
        {'username': 42},
      ]) {
        await expectLater(
          codec.decode(
            _plaintext({
              'smb': [
                {..._smbJson, ...field},
              ],
            }),
          ),
          _problem(BackupProblem.invalid),
          reason: field.keys.single,
        );
      }
      for (final invalid in [
        null,
        _smbJson,
        [null],
        [Map.of(_smbJson)..remove('domain')],
      ]) {
        await expectLater(
          codec.decode(_plaintext({'smb': invalid})),
          _problem(BackupProblem.invalid),
        );
      }
      await expectLater(
        codec.encode(ConfigurationBackup(smb: [_smbWith(password: _secret)])),
        _problem(BackupProblem.invalid),
      );
    },
  );

  test(
    'encrypted v2 protects SMB data and authenticates the version',
    () async {
      final record = _smbWith(password: _secret);
      final bytes = await codec.encode(
        ConfigurationBackup(smb: [record]),
        passphrase: _passphrase,
      );
      final envelope = _json(bytes);
      expect(envelope['version'], 2);
      expect(codec.isEncrypted(bytes), isTrue);
      expect(envelope, isNot(contains('data')));
      for (final value in [
        _secret,
        record.host,
        record.share,
        record.username,
      ]) {
        expect(utf8.decode(bytes), isNot(contains(value)));
      }
      final decoded = await codec.decode(bytes, passphrase: _passphrase);
      expect(decoded.smb, [record]);
      expect(decoded.hasCredentials(BackupSection.smb), isTrue);

      final downgraded = utf8.encode(jsonEncode(envelope..['version'] = 1));
      await expectLater(
        codec.decode(downgraded, passphrase: _passphrase),
        _problem(BackupProblem.unlockFailed),
      );
    },
  );

  test('preview deduplicates SMB scopes independently of WebDAV', () {
    const existing = SmbConnection(
      id: 'local',
      name: 'Local library',
      host: 'NAS.TEST.',
      share: 'movie library',
      domain: 'office',
      username: 'READER',
      password: 'local secret',
    );
    final otherDomain = _smbWith(domain: 'ANOTHER');
    final otherShare = _smbWith(share: 'Shows');
    final preview = ConfigurationImportPreview(
      backup: ConfigurationBackup(
        webdav: [_dav],
        smb: [
          _smb,
          otherDomain,
          _smbWith(domain: 'another', password: _secret),
          otherShare,
        ],
      ),
      existing: [
        WebDavConnection(
          id: 'dav',
          name: 'Local WebDAV',
          url: _dav.url,
          username: _dav.username,
        ),
      ],
      existingSmb: [existing],
      globals: const ConnectionSettings(),
    );
    expect(preview.additions, isEmpty);
    expect(preview.skipped, 1);
    expect(preview.smbAdditions, [otherDomain, otherShare]);
    expect(preview.smbSkipped, 2);
  });
}
