import 'package:azusa/core/database/app_database.dart';
import 'package:azusa/features/organizer/connections/connection_settings.dart';
import 'package:azusa/features/organizer/connections/webdav_connections.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

class MemorySecrets extends FlutterSecureStorage {
  final values = <String, String>{};
  final reads = <String>[];
  final writes = <String>[];
  final deletes = <String>[];
  bool failWrite = false;
  bool failDelete = false;
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
    reads.add(key);
    return values[key];
  }

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
    if (failWrite) throw StateError('secure storage unavailable');
    if (value != null) values[key] = value;
  }

  @override
  Future<void> delete({
    required String key,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic wOptions,
    dynamic mOptions,
    dynamic webOptions,
  }) async {
    deletes.add(key);
    if (failDelete) throw StateError('secure storage unavailable');
    values.remove(key);
  }
}

void main() {
  late AppDatabase database;
  late MemorySecrets secrets;
  late WebDavConnectionsRepository repository;
  const first = WebDavConnection(
    id: 'one',
    name: 'NAS',
    url: 'https://one.test/dav/',
    username: 'user',
    password: 'secret-one',
  );
  const second = WebDavConnection(
    id: 'two',
    name: 'NAS 2',
    url: 'https://two.test/dav/',
    password: 'secret-two',
    useProxy: true,
  );

  setUp(() async {
    database = AppDatabase(open: () async => sqlite3.openInMemory());
    secrets = MemorySecrets();
    repository = WebDavConnectionsRepository(database, secrets);
    await repository.initialize(const ConnectionSettings());
  });
  tearDown(() => database.close());

  test('保存、切换及删除持久化，密码按连接隔离且不进入数据库', () async {
    await repository.save(first, activate: true);
    await repository.save(second);
    expect(await repository.activeId(), first.id);
    final loaded = await repository.load();
    expect(loaded.map((item) => item.password), ['secret-one', 'secret-two']);
    expect(loaded.last.useProxy, isTrue);
    final db = await database.connection();
    expect(
      db.select('SELECT * FROM webdav_connections').first.values,
      isNot(contains('secret-one')),
    );
    await repository.select(second.id);
    expect(await repository.activeId(), second.id);
    final reopened = WebDavConnectionsRepository(database, secrets);
    expect(await reopened.activeId(), second.id);
    expect((await reopened.load()).length, 2);
    await repository.remove(second.id);
    expect(await repository.activeId(), isNull);
    expect((await repository.load()).single.password, first.password);
    expect(secrets.values.length, 1);
    await expectLater(repository.select('missing'), throwsStateError);
  });

  test('安全存储写入失败不改变已有配置及密码', () async {
    await repository.save(first, activate: true);
    secrets.failWrite = true;
    await expectLater(
      repository.save(
        WebDavConnection(
          id: first.id,
          name: 'Changed',
          url: first.url,
          password: 'new',
        ),
      ),
      throwsStateError,
    );
    final loaded = (await repository.load()).single;
    expect(loaded.name, first.name);
    expect(loaded.password, first.password);
  });

  test('数据库提交失败清理新密码且保留旧记录', () async {
    await repository.save(first);
    (await database.connection()).execute(
      "CREATE TRIGGER reject_update BEFORE UPDATE ON webdav_connections BEGIN SELECT RAISE(ABORT, 'failure'); END",
    );
    await expectLater(
      repository.save(
        WebDavConnection(
          id: first.id,
          name: 'Changed',
          url: first.url,
          password: 'changed-password',
        ),
      ),
      throwsA(isA<SqliteException>()),
    );
    expect(secrets.values.length, 1);
    expect((await repository.load()).single.password, first.password);
  });

  test('旧密码清理失败不影响已提交的新配置', () async {
    await repository.save(first);
    secrets.failDelete = true;
    await repository.save(
      WebDavConnection(
        id: first.id,
        name: first.name,
        url: first.url,
        password: 'new',
      ),
    );
    expect((await repository.load()).single.password, 'new');
  });

  test('旧配置迁移可重试且删除后不会复活', () async {
    final db = await database.connection();
    db.execute('UPDATE webdav_state SET migrated = 0');
    const legacy = ConnectionSettings(
      webdavUrl: 'https://legacy.test/dav/',
      username: 'legacy-user',
      webdavPassword: 'legacy-password',
      proxyWebdav: true,
    );
    secrets.failWrite = true;
    await expectLater(repository.initialize(legacy), throwsStateError);
    expect(
      db.select('SELECT migrated FROM webdav_state').single['migrated'],
      0,
    );
    secrets.failWrite = false;
    repository.credentials.retryFailedLoad();
    await repository.initialize(legacy);
    await repository.initialize(legacy);
    final loaded = (await repository.load()).single;
    expect(loaded.password, legacy.webdavPassword);
    expect(loaded.useProxy, isTrue);
    expect(await repository.activeId(), loaded.id);
    await repository.remove(loaded.id);
    await repository.initialize(legacy);
    expect(await repository.load(), isEmpty);
  });

  test('拒绝无效地址及空名称', () async {
    await expectLater(
      repository.save(
        const WebDavConnection(
          id: 'invalid',
          name: '',
          url: 'https://nas.test/',
        ),
      ),
      throwsFormatException,
    );
    await expectLater(
      repository.save(
        const WebDavConnection(
          id: 'invalid',
          name: 'NAS',
          url: 'https://nas.test/?q=1',
        ),
      ),
      throwsFormatException,
    );
    expect(secrets.values, isEmpty);
  });
}
