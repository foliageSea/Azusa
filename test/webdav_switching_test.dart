import 'dart:async';

import 'package:azusa/core/database/app_database.dart';
import 'package:azusa/features/organizer/connections/connection_settings.dart';
import 'package:azusa/features/organizer/connections/webdav_connections.dart';
import 'package:azusa/features/organizer/dav/webdav.dart';
import 'package:azusa/features/organizer/organizer_state.dart';
import 'package:azusa/features/organizer/rename_plan.dart';
import 'package:azusa/features/organizer/startup_connection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

import 'webdav_connections_test.dart' show MemorySecrets;

class MemoryPreferences implements SharedPreferencesAsync {
  final values = <String, String>{};
  @override
  Future<String?> getString(String key) async => values[key];
  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class SwitchingOrganizer extends OrganizerController {
  @override
  OrganizerState build() => const OrganizerState(
    directory: '/dav/old/',
    entries: [DavEntry('/dav/old/a.mkv', false)],
    plan: [
      RenameItem(
        source: '/dav/old/a.mkv',
        targetName: 'new.mkv',
        reason: 'test',
      ),
    ],
  );
  void lock() {
    state = state.copyWith(busy: true);
  }
}

class SwitchingDav extends WebDavClient {
  SwitchingDav(super.settings, {this.fail = false, this.pending});
  final bool fail;
  final Future<void>? pending;
  bool closed = false;
  @override
  Future<List<DavEntry>> list(String path) async {
    await pending;
    if (fail) throw StateError('模拟失败');
    return [DavEntry('$root${settings.username}.mkv', false)];
  }

  @override
  void close() {
    closed = true;
    super.close();
  }
}

void main() {
  late AppDatabase database;
  late WebDavConnectionsRepository repository;
  late ProviderContainer container;
  late MemoryPreferences preferences;
  late MemorySecrets secrets;
  late WebDavClient Function(ConnectionSettings) factory;
  const one = WebDavConnection(
    id: 'one',
    name: 'One',
    url: 'https://one.test/dav/',
    username: 'one',
    password: 'one-password',
  );
  const two = WebDavConnection(
    id: 'two',
    name: 'Two',
    url: 'https://two.test/dav/',
    username: 'two',
    password: 'two-password',
    useProxy: true,
  );

  setUp(() async {
    database = AppDatabase(open: () async => sqlite3.openInMemory());
    preferences = MemoryPreferences();
    secrets = MemorySecrets();
    repository = WebDavConnectionsRepository(database, secrets);
    await repository.initialize(const ConnectionSettings());
    await repository.save(one, activate: true);
    await repository.save(two);
    factory = (settings) => SwitchingDav(settings);
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        connectionRepositoryProvider.overrideWithValue(
          ConnectionRepository(preferences, secrets),
        ),
        organizerProvider.overrideWith(SwitchingOrganizer.new),
        webDavFactoryProvider.overrideWithValue(
          (settings) => factory(settings),
        ),
      ],
    );
    await container.read(connectionSettingsProvider.future);
  });
  tearDown(() async {
    container.dispose();
    await database.close();
  });

  test('切换清空预览并读取新服务根目录，保留共享设置', () async {
    final controller = container.read(connectionSettingsProvider.notifier);
    await controller.save(
      container
          .read(connectionSettingsProvider)
          .requireValue
          .copyWith(model: 'global-model', aiKey: 'global-key'),
    );
    await controller.selectConnection(two.id);
    final settings = container.read(connectionSettingsProvider).requireValue;
    expect(settings.connectionId, two.id);
    expect(settings.webdavPassword, two.password);
    expect(settings.proxyWebdav, isTrue);
    expect(settings.model, 'global-model');
    expect(settings.aiKey, 'global-key');
    final state = container.read(organizerProvider);
    expect(state.plan, isEmpty);
    expect(state.directory, '/dav/');
    expect(state.entries.single.name, 'two.mkv');
    expect(await repository.activeId(), two.id);
    expect(preferences.values.values.single, isNot(contains('two-password')));
  });

  test('新服务连接失败不残留旧目录和预览', () async {
    factory = (settings) => SwitchingDav(settings, fail: true);
    await container
        .read(connectionSettingsProvider.notifier)
        .selectConnection(two.id);
    final state = container.read(organizerProvider);
    expect(state.directory, isEmpty);
    expect(state.entries, isEmpty);
    expect(state.plan, isEmpty);
    expect(state.message, contains('读取目录失败'));
    expect(state.busy, isFalse);
  });

  test('文件操作期间拒绝切换、保存和删除', () async {
    (container.read(organizerProvider.notifier) as SwitchingOrganizer).lock();
    final controller = container.read(connectionSettingsProvider.notifier);
    await expectLater(controller.selectConnection(two.id), throwsStateError);
    await expectLater(controller.saveConnection(one), throwsStateError);
    await expectLater(controller.deleteConnection(one.id), throwsStateError);
    expect(await repository.activeId(), one.id);
  });

  test('切换请求未结束时拒绝第二次切换', () async {
    final pending = Completer<void>();
    factory = (settings) => SwitchingDav(settings, pending: pending.future);
    final controller = container.read(connectionSettingsProvider.notifier);
    final switchFuture = controller.selectConnection(two.id);
    while (!container.read(organizerProvider).busy ||
        container.read(connectionSettingsProvider).requireValue.connectionId !=
            two.id) {
      await Future<void>.delayed(Duration.zero);
    }
    await expectLater(controller.selectConnection(one.id), throwsStateError);
    pending.complete();
    await switchFuture;
    expect(container.read(organizerProvider).entries.single.name, 'two.mkv');
  });

  test('删除非当前连接保留预览，删除当前连接清空且不自动切换', () async {
    final controller = container.read(connectionSettingsProvider.notifier);
    await controller.deleteConnection(two.id);
    expect(container.read(organizerProvider).plan, isNotEmpty);
    await controller.deleteConnection(one.id);
    expect(
      container.read(connectionSettingsProvider).requireValue.connectionId,
      isNull,
    );
    expect(
      container.read(connectionSettingsProvider).requireValue.webdavUrl,
      isEmpty,
    );
    expect(container.read(organizerProvider).entries, isEmpty);
  });

  test('重建容器后恢复最后连接并在启动时连接', () async {
    await repository.select(two.id);
    container.dispose();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        connectionRepositoryProvider.overrideWithValue(
          ConnectionRepository(preferences, secrets),
        ),
        webDavFactoryProvider.overrideWithValue(
          (settings) => SwitchingDav(settings),
        ),
      ],
    );
    await container.read(startupConnectionProvider.future);
    expect(
      container.read(connectionSettingsProvider).requireValue.connectionId,
      two.id,
    );
    expect(container.read(organizerProvider).entries.single.name, 'two.mkv');
  });
}
