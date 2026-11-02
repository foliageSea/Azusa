import 'dart:async';

import 'package:azusa/features/organizer/connections/connection_settings.dart';
import 'package:azusa/features/organizer/dav/webdav.dart';
import 'package:azusa/features/organizer/organizer_state.dart';
import 'package:azusa/features/organizer/startup_connection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class SavedConnections extends ConnectionSettingsController {
  SavedConnections(this.settings);
  final Future<ConnectionSettings> settings;

  @override
  Future<ConnectionSettings> build() => settings;

  @override
  Future<void> save(ConnectionSettings value) async {
    state = AsyncData(value);
  }
}

class StartupDav extends WebDavClient {
  StartupDav(super.settings);
  int requests = 0;
  bool fail = false;
  bool closed = false;

  @override
  Future<List<DavEntry>> list(String path) async {
    requests++;
    if (fail) throw StateError('模拟连接失败');
    return [DavEntry('${root}episode.mkv', false)];
  }

  @override
  void close() {
    closed = true;
    super.close();
  }
}

void main() {
  const settings = ConnectionSettings(
    webdavUrl: 'https://nas.test/dav/',
    username: 'saved-user',
    webdavPassword: 'saved-password',
  );

  test('等待已保存配置加载后自动连接根目录，断开及保存后不自动重连', () async {
    final loaded = Completer<ConnectionSettings>();
    final dav = StartupDav(settings);
    final container = ProviderContainer(
      overrides: [
        connectionSettingsProvider.overrideWith(
          () => SavedConnections(loaded.future),
        ),
        webDavFactoryProvider.overrideWithValue((value) {
          expect(value.username, settings.username);
          expect(value.webdavPassword, settings.webdavPassword);
          return dav;
        }),
      ],
    );
    addTearDown(container.dispose);
    final startup = container.read(startupConnectionProvider.future);
    expect(dav.requests, 0);
    loaded.complete(settings);
    await startup;

    expect(dav.requests, 1);
    expect(dav.closed, isTrue);
    expect(container.read(organizerProvider).directory, '/dav/');
    expect(
      container.read(organizerProvider).entries.single.name,
      'episode.mkv',
    );
    expect(container.read(organizerProvider).busy, isFalse);

    container.read(organizerProvider.notifier).disconnect();
    await container.read(connectionSettingsProvider.notifier).save(settings);
    await container.read(startupConnectionProvider.future);
    expect(dav.requests, 1);
    expect(container.read(organizerProvider).directory, isEmpty);
  });

  test('未配置 WebDAV 地址时不连接', () async {
    final container = ProviderContainer(
      overrides: [
        connectionSettingsProvider.overrideWith(
          () => SavedConnections(Future.value(const ConnectionSettings())),
        ),
        webDavFactoryProvider.overrideWithValue((_) {
          fail('未配置地址不应创建 WebDAV 客户端');
        }),
      ],
    );
    addTearDown(container.dispose);
    await container.read(startupConnectionProvider.future);
    expect(container.read(organizerProvider).directory, isEmpty);
    expect(container.read(organizerProvider).busy, isFalse);
  });

  test('自动连接失败后保留错误状态，允许手动重试', () async {
    final dav = StartupDav(settings)..fail = true;
    final container = ProviderContainer(
      overrides: [
        connectionSettingsProvider.overrideWith(
          () => SavedConnections(Future.value(settings)),
        ),
        webDavFactoryProvider.overrideWithValue((_) => dav),
      ],
    );
    addTearDown(container.dispose);
    await container.read(startupConnectionProvider.future);
    expect(container.read(organizerProvider).directory, isEmpty);
    expect(container.read(organizerProvider).hasError, isTrue);
    expect(container.read(organizerProvider).busy, isFalse);
    expect(dav.closed, isTrue);

    dav.fail = false;
    await container.read(organizerProvider.notifier).open(null);
    expect(dav.requests, 2);
    expect(container.read(organizerProvider).directory, '/dav/');
    expect(container.read(organizerProvider).message, isEmpty);
  });
}
