import 'dart:convert';

import 'package:azusa/core/database/app_database.dart';
import 'package:azusa/features/organizer/connections/credential_vault.dart';
import 'package:azusa/features/organizer/connections/connection_settings.dart';
import 'package:azusa/features/organizer/connections/webdav_connections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'webdav_connections_test.dart' show MemorySecrets;
import 'webdav_switching_test.dart' show MemoryPreferences;

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

class UnverifiedSecrets extends MemorySecrets {
  @override
  Future<void> write({
    required String key,
    required String? value,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic wOptions,
    dynamic mOptions,
    dynamic webOptions,
  }) async {
    writes.add(key);
  }
}

void main() {
  test('macOS 服务标识和显示名称独立于旧插件默认服务', () {
    expect(
      CredentialVault.macOsOptions.accountName,
      'com.foliage.azusa.credentials',
    );
    expect(CredentialVault.macOsOptions.label, 'Azusa 凭据');
    expect(CredentialVault.macOsOptions.usesDataProtectionKeychain, isFalse);
    expect(
      CredentialVault.legacyMacOsOptions.accountName,
      'flutter_secure_storage_service',
    );
    expect(CredentialVault.legacyMacOsOptions.label, isNull);
  });

  test('旧默认服务的统一仓库完整迁移到命名服务，不清理无关条目', () async {
    final legacy = MemorySecrets()
      ..values.addAll({
        CredentialVault.storageKey: jsonEncode({
          'version': 1,
          'values': {'azusa.aiKey': 'ai', 'dav-reference': 'password'},
        }),
        'unrelated': 'keep',
      });
    final storage = MemorySecrets();
    final vault = CredentialVault.forStorage(storage, legacyStorage: legacy);
    expect(await vault.read('dav-reference'), 'password');
    expect(await vault.read('azusa.aiKey'), 'ai');
    expect(legacy.reads, [CredentialVault.storageKey]);
    expect(legacy.deletes, [CredentialVault.storageKey]);
    expect(legacy.values, {'unrelated': 'keep'});
    final restarted = MemorySecrets()..values.addAll(storage.values);
    final untouched = MemorySecrets();
    expect(
      await CredentialVault.forStorage(
        restarted,
        legacyStorage: untouched,
      ).read('azusa.aiKey'),
      'ai',
    );
    expect(untouched.reads, isEmpty);
  });

  test('旧默认服务的独立凭据迁移到命名服务', () async {
    final legacy = MemorySecrets()
      ..values.addAll({'azusa.aiKey': 'ai', 'old-webdav': 'dav'});
    final storage = MemorySecrets();
    final vault = CredentialVault.forStorage(storage, legacyStorage: legacy)
      ..legacyWebDavKeys = () async => ['old-webdav'];
    expect(await vault.read('old-webdav'), 'dav');
    expect(await vault.read('azusa.aiKey'), 'ai');
    expect(storage.values.keys, [CredentialVault.storageKey]);
    expect(legacy.values, isEmpty);
    expect(storage.deletes, isEmpty);
  });

  test('跨服务迁移失败保留旧仓库，目标仓库损坏不回退覆盖', () async {
    final raw = jsonEncode({
      'version': 1,
      'values': {'ai': 'original'},
    });
    for (final storage in [
      MemorySecrets()..failWrite = true,
      UnverifiedSecrets(),
    ]) {
      final legacy = MemorySecrets()..values[CredentialVault.storageKey] = raw;
      await expectLater(
        CredentialVault.forStorage(storage, legacyStorage: legacy).read('ai'),
        throwsStateError,
      );
      expect(legacy.values[CredentialVault.storageKey], raw);
      expect(legacy.deletes, isEmpty);
    }
    final legacy = MemorySecrets()..values[CredentialVault.storageKey] = raw;
    final invalid = MemorySecrets()
      ..values[CredentialVault.storageKey] = 'broken';
    await expectLater(
      CredentialVault.forStorage(invalid, legacyStorage: legacy).read('ai'),
      throwsFormatException,
    );
    expect(legacy.reads, isEmpty);
    expect(invalid.writes, isEmpty);
  });

  test('旧条目清理失败不丢数据，后续启动不再次尝试清理', () async {
    final storage = MemorySecrets()..failDelete = true;
    storage.values['azusa.aiKey'] = 'original';
    expect(
      await CredentialVault.forStorage(storage).read('azusa.aiKey'),
      'original',
    );
    final restarted = MemorySecrets()..values.addAll(storage.values);
    expect(
      await CredentialVault.forStorage(restarted).read('azusa.aiKey'),
      'original',
    );
    expect(restarted.reads, [CredentialVault.storageKey]);
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

  test('v0.0.2 配置与密码完整升级到多连接及统一仓库', () async {
    final database = AppDatabase(open: () async => sqlite3.openInMemory());
    addTearDown(database.close);
    final storage = MemorySecrets()
      ..values.addAll({
        'azusa.webdavPassword': 'dav-password',
        'azusa.aiKey': 'ai-key',
        'azusa.tmdbToken': 'tmdb-token',
      });
    final preferences = MemoryPreferences();
    preferences.values['azusa.connections.v1'] = jsonEncode({
      'webdavUrl': 'https://nas.test/dav/',
      'username': 'user',
      'model': 'model',
    });
    final globals = ConnectionRepository(preferences, storage);
    final connections = WebDavConnectionsRepository(database, storage);
    final loaded = await globals.load();
    await connections.initialize(loaded);
    expect(loaded.aiKey, 'ai-key');
    expect(loaded.tmdbToken, 'tmdb-token');
    expect((await connections.load()).single.password, 'dav-password');
    expect(await connections.activeId(), 'legacy');
    expect(storage.values.keys, [CredentialVault.storageKey]);
    final reads = storage.reads.length;
    final writes = storage.writes.length;
    await globals.save(loaded.copyWith(model: 'other'), includeWebdav: false);
    await connections.initialize(loaded);
    expect(storage.reads.length, reads);
    expect(storage.writes.length, writes);
  });

  test('旧版三个凭据一次迁移，重启仅访问一个系统条目', () async {
    final storage = MemorySecrets();
    storage.values.addAll({
      'azusa.webdavPassword': 'dav',
      'azusa.aiKey': 'ai',
      'azusa.tmdbToken': 'tmdb',
    });
    final vault = CredentialVault.forStorage(storage);
    expect(await vault.read('azusa.webdavPassword'), 'dav');
    expect(await vault.read('azusa.aiKey'), 'ai');
    expect(await vault.read('azusa.tmdbToken'), 'tmdb');
    expect(storage.values.keys, [CredentialVault.storageKey]);
    final before = storage.reads.length;
    await Future.wait(List.generate(10, (_) => vault.read('azusa.aiKey')));
    expect(storage.reads.length, before);
    final restarted = MemorySecrets()..values.addAll(storage.values);
    expect(
      await CredentialVault.forStorage(restarted).read('azusa.aiKey'),
      'ai',
    );
    expect(restarted.reads, [CredentialVault.storageKey]);
    expect(restarted.writes, isEmpty);
    expect(restarted.deletes, isEmpty);
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
    storage.denied = false;
    vault.retryFailedLoad();
    expect(await vault.read('ai'), isNull);
  });

  test('迁移写入或验证失败不删除任何旧凭据', () async {
    for (final storage in [
      MemorySecrets()..failWrite = true,
      UnverifiedSecrets(),
    ]) {
      storage.values['azusa.aiKey'] = 'original';
      await expectLater(
        CredentialVault.forStorage(storage).read('azusa.aiKey'),
        throwsStateError,
      );
      expect(storage.values['azusa.aiKey'], 'original');
      expect(storage.deletes, isEmpty);
    }
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
      final storage = MemorySecrets()..values[CredentialVault.storageKey] = raw;
      await expectLater(
        CredentialVault.forStorage(storage).read('ai'),
        throwsFormatException,
      );
      expect(storage.writes, isEmpty);
      expect(storage.deletes, isEmpty);
    }
  });

  test('多连接旧条目迁移，列表不读密码且修改名称不写凭据', () async {
    final database = AppDatabase(open: () async => sqlite3.openInMemory());
    addTearDown(database.close);
    final db = await database.connection();
    db.execute(
      "INSERT INTO webdav_connections VALUES ('one','NAS','https://nas.test/','user',0,'old-one')",
    );
    db.execute(
      "INSERT INTO webdav_connections VALUES ('two','NAS 2','https://two.test/','user',0,'old-two')",
    );
    db.execute('UPDATE webdav_state SET migrated = 1');
    final storage = MemorySecrets()
      ..values.addAll({
        'old-one': 'one-pass',
        'old-two': 'two-pass',
        'azusa.aiKey': 'ai',
      });
    final repository = WebDavConnectionsRepository(database, storage);
    await repository.initialize(const ConnectionSettings());
    final metadata = await repository.load(includePasswords: false);
    expect(storage.reads, isEmpty);
    expect(metadata.every((value) => value.password.isEmpty), isTrue);
    final one = await repository.withPassword(metadata.first);
    expect(one.password, 'one-pass');
    expect((await repository.withPassword(metadata.last)).password, 'two-pass');
    expect(storage.values.keys, [CredentialVault.storageKey]);
    final reads = storage.reads.length;
    final writes = storage.writes.length;
    await repository.save(
      WebDavConnection(
        id: one.id,
        name: 'Renamed',
        url: one.url,
        password: one.password,
      ),
    );
    expect(storage.reads.length, reads);
    expect(storage.writes.length, writes);
    expect((await repository.load()).first.name, 'Renamed');
  });
}
