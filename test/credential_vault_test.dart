import 'dart:convert';

import 'package:azusa/core/database/app_database.dart';
import 'package:azusa/features/organizer/connections/credential_vault.dart';
import 'package:azusa/features/organizer/connections/connection_settings.dart';
import 'package:azusa/features/organizer/connections/webdav_connections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'webdav_connections_test.dart' show MemorySecrets;

class DeniedSecrets extends MemorySecrets {
  bool denied = true;
  @override
  Future<String?> read({
    required String key,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic wOptions,
    dynamic mOptions,
    dynamic webOptions,
  }) async {
    if (denied) {
      reads.add(key);
      throw StateError('denied');
    }
    return super.read(key: key);
  }
}

void main() {
  test('macOS 使用单一命名服务和 JSON 条目', () {
    expect(
      CredentialVault.macOsOptions.accountName,
      'com.foliage.azusa.credentials',
    );
    expect(CredentialVault.macOsOptions.label, 'Azusa 凭据');
    expect(CredentialVault.macOsOptions.usesDataProtectionKeychain, isFalse);
    expect(CredentialVault.storageKey, 'azusa.credentials.v1');
  });

  test('首次创建空仓库，不读取或删除旧独立凭据', () async {
    final oldValues = {
      'azusa.webdavPassword': 'old-dav',
      'azusa.aiKey': 'old-ai',
      'azusa.tmdbToken': 'old-tmdb',
      'old-webdav-reference': 'old-password',
    };
    final storage = MemorySecrets()..values.addAll(oldValues);
    final vault = CredentialVault.forStorage(storage);
    expect(await vault.read('azusa.aiKey'), isNull);
    expect(await vault.read('old-webdav-reference'), isNull);
    expect(storage.reads, [CredentialVault.storageKey]);
    expect(storage.writes, [CredentialVault.storageKey]);
    expect(storage.deletes, isEmpty);
    expect(jsonDecode(storage.values[CredentialVault.storageKey]!), {
      'version': 1,
      'values': <String, String>{},
    });
    for (final entry in oldValues.entries) {
      expect(storage.values[entry.key], entry.value);
    }
  });

  test('重启仅读取当前 JSON 仓库，不写入或清理条目', () async {
    final storage = MemorySecrets();
    final vault = CredentialVault.forStorage(storage);
    await vault.update({
      'azusa.aiKey': 'ai',
      'azusa.tmdbToken': 'tmdb',
      'dav-reference': 'dav',
    });
    final restarted = MemorySecrets()..values.addAll(storage.values);
    final reopened = CredentialVault.forStorage(restarted);
    expect(await reopened.read('azusa.aiKey'), 'ai');
    expect(await reopened.read('azusa.tmdbToken'), 'tmdb');
    expect(await reopened.read('dav-reference'), 'dav');
    expect(restarted.reads, [CredentialVault.storageKey]);
    expect(restarted.writes, isEmpty);
    expect(restarted.deletes, isEmpty);
  });

  test('损坏的 JSON 不在异常中泄露凭据', () async {
    final storage = MemorySecrets()
      ..values[CredentialVault.storageKey] =
          '{"password":"private-secret",broken';
    try {
      await CredentialVault.forStorage(storage).read('ai');
      fail('Expected invalid vault');
    } on FormatException catch (e) {
      expect(e.toString(), isNot(contains('private-secret')));
      expect(e.source, isNull);
    }
  });

  test('并发读取合并，串行更新不同凭据不会互相覆盖', () async {
    final storage = MemorySecrets()
      ..values[CredentialVault.storageKey] = jsonEncode({
        'version': 1,
        'values': <String, String>{},
      });
    final vault = CredentialVault.forStorage(storage);
    await Future.wait(List.generate(10, (_) => vault.read('ai')));
    expect(storage.reads, [CredentialVault.storageKey]);
    await Future.wait([
      vault.write('ai', 'one'),
      vault.write('dav', 'two'),
      vault.write('tmdb', 'three'),
    ]);
    expect(await vault.read('ai'), 'one');
    expect(await vault.read('dav'), 'two');
    expect(await vault.read('tmdb'), 'three');
    final count = storage.writes.length;
    await vault.write('ai', 'one');
    expect(storage.writes.length, count);
    expect(
      storage.writes.every((key) => key == CredentialVault.storageKey),
      isTrue,
    );
  });

  test('拒绝授权不自动重试，显式重试后可恢复', () async {
    final storage = DeniedSecrets();
    final vault = CredentialVault.forStorage(storage);
    await expectLater(vault.read('ai'), throwsStateError);
    await expectLater(vault.read('dav'), throwsStateError);
    expect(storage.reads.length, 1);
    expect(storage.writes, isEmpty);
    storage.denied = false;
    vault.retryFailedLoad();
    expect(await vault.read('ai'), isNull);
  });

  test('首次初始化写入失败不自动重试，显式重试后创建空仓库', () async {
    final storage = MemorySecrets()..failWrite = true;
    final vault = CredentialVault.forStorage(storage);
    await expectLater(vault.read('ai'), throwsStateError);
    await expectLater(vault.read('dav'), throwsStateError);
    expect(storage.reads, [CredentialVault.storageKey]);
    expect(storage.writes, [CredentialVault.storageKey]);
    expect(storage.values, isEmpty);
    storage.failWrite = false;
    vault.retryFailedLoad();
    expect(await vault.read('ai'), isNull);
    expect(storage.values.keys, [CredentialVault.storageKey]);
  });

  test('写入失败保持缓存和已保存值，后续更新可重试', () async {
    final storage = MemorySecrets();
    final vault = CredentialVault.forStorage(storage);
    await vault.write('ai', 'original');
    storage.failWrite = true;
    await expectLater(vault.write('ai', 'changed'), throwsStateError);
    expect(await vault.read('ai'), 'original');
    storage.failWrite = false;
    await vault.write('ai', 'changed');
    expect(await vault.read('ai'), 'changed');
  });

  test('无效或高版本仓库不覆盖、不回退旧数据', () async {
    for (final raw in [
      'broken',
      '{"version":2,"values":{}}',
      '{"version":1,"values":{"ai":12}}',
    ]) {
      final storage = MemorySecrets()
        ..values[CredentialVault.storageKey] = raw
        ..values['azusa.aiKey'] = 'old-ai';
      await expectLater(
        CredentialVault.forStorage(storage).read('azusa.aiKey'),
        throwsFormatException,
      );
      expect(storage.reads, [CredentialVault.storageKey]);
      expect(storage.writes, isEmpty);
      expect(storage.deletes, isEmpty);
    }
  });

  test('多连接共享 JSON 仓库，列表不读密码且修改名称不写凭据', () async {
    final database = AppDatabase(open: () async => sqlite3.openInMemory());
    addTearDown(database.close);
    final db = await database.connection();
    db.execute(
      "INSERT INTO webdav_connections VALUES ('one','NAS','https://nas.test/','user',0,'one-ref')",
    );
    db.execute(
      "INSERT INTO webdav_connections VALUES ('two','NAS 2','https://two.test/','user',0,'two-ref')",
    );
    db.execute('UPDATE webdav_state SET migrated = 1');
    final storage = MemorySecrets()
      ..values[CredentialVault.storageKey] = jsonEncode({
        'version': 1,
        'values': {'one-ref': 'one-pass', 'two-ref': 'two-pass'},
      });
    final repository = WebDavConnectionsRepository(database, storage);
    await repository.initialize(const ConnectionSettings());
    final metadata = await repository.load(includePasswords: false);
    expect(storage.reads, isEmpty);
    expect(metadata.every((value) => value.password.isEmpty), isTrue);
    final one = await repository.withPassword(metadata.first);
    expect(one.password, 'one-pass');
    expect((await repository.withPassword(metadata.last)).password, 'two-pass');
    expect(storage.reads, [CredentialVault.storageKey]);
    final writes = storage.writes.length;
    await repository.save(
      WebDavConnection(
        id: one.id,
        name: 'Renamed',
        url: one.url,
        password: one.password,
      ),
    );
    expect(storage.reads, [CredentialVault.storageKey]);
    expect(storage.writes.length, writes);
    expect((await repository.load()).first.name, 'Renamed');
  });
}
