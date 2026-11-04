import 'dart:io';
import 'dart:convert';

import 'package:azusa/features/organizer/connections/connection_settings.dart';
import 'package:azusa/features/organizer/connections/http_clients.dart';
import 'package:azusa/features/organizer/connections/system_proxy.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('持久化迁移旧配置并保存系统模式、手动地址及服务开关', () async {
    final preferences = _MemoryPreferences();
    final repository = ConnectionRepository(preferences, _EmptySecrets());
    preferences.raw = jsonEncode({'proxyUrl': 'http://localhost:7890'});
    final legacy = await repository.load();
    expect(legacy.proxyMode, ProxyMode.manual);
    await repository.save(
      legacy.copyWith(
        proxyMode: ProxyMode.system,
        proxyAi: false,
        proxyWebdav: true,
      ),
    );
    final loaded = await repository.load();
    expect(loaded.proxyMode, ProxyMode.system);
    expect(loaded.proxyUrl, 'http://localhost:7890');
    expect(loaded.proxyAi, isFalse);
    expect(loaded.proxyWebdav, isTrue);
    preferences.raw = '{}';
    expect((await repository.load()).proxyMode, ProxyMode.direct);
  });

  test('旧配置保持原代理模式，显式模式不依赖手动地址', () {
    expect(const ConnectionSettings().proxyMode, ProxyMode.direct);
    const legacy = ConnectionSettings(proxyUrl: 'http://localhost:7890');
    expect(legacy.proxyMode, ProxyMode.manual);
    final system = legacy.copyWith(proxyMode: ProxyMode.system);
    expect(system.copyWith(model: 'new').proxyMode, ProxyMode.system);
    expect(usesProxy(system, NetworkService.ai), isTrue);
    expect(usesProxy(system, NetworkService.tmdb), isTrue);
    expect(usesProxy(system, NetworkService.webdav), isFalse);
    expect(
      usesProxy(
        system.copyWith(proxyMode: ProxyMode.direct),
        NetworkService.ai,
      ),
      isFalse,
    );
    expect(
      usesProxy(
        const ConnectionSettings(proxyMode: ProxyMode.system),
        NetworkService.ai,
      ),
      isTrue,
    );
  });

  test('环境变量区分协议并遵循 NO_PROXY 和小写优先规则', () {
    final environment = {
      'http_proxy': 'http://127.0.0.1:7890',
      'HTTP_PROXY': 'other:8080',
      'HTTPS_PROXY': 'secure:7891',
      'NO_PROXY': 'localhost,.internal',
    };
    expect(
      SystemProxy.environmentProxy(
        Uri.parse('http://example.test'),
        environment,
      ),
      'PROXY 127.0.0.1:7890',
    );
    expect(
      SystemProxy.environmentProxy(
        Uri.parse('https://example.test'),
        environment,
      ),
      'PROXY secure:7891',
    );
    expect(
      SystemProxy.environmentProxy(
        Uri.parse('https://nas.internal'),
        environment,
      ),
      'DIRECT',
    );
    expect(
      SystemProxy.environmentProxy(Uri.parse('http://localhost'), environment),
      'DIRECT',
    );
    expect(
      SystemProxy.environmentProxy(Uri.parse('http://example.test'), {}),
      isNull,
    );
    expect(
      () => SystemProxy.environmentProxy(Uri.parse('http://example.test'), {
        'http_proxy': 'socks5://localhost:1080',
      }),
      throwsStateError,
    );
  });

  test('系统返回代理链、IPv6 和直连，拒绝认证及不支持的代理', () {
    expect(
      SystemProxy.normalize(['http://127.0.0.1:7890', 'direct://']),
      'PROXY 127.0.0.1:7890; DIRECT',
    );
    expect(SystemProxy.normalize(['http://[::1]:7890']), 'PROXY [::1]:7890');
    for (final proxy in [
      'socks5://localhost:1080',
      'http://u:p@localhost:7890',
      'http://localhost:0',
      'http://localhost',
    ]) {
      expect(() => SystemProxy.normalize([proxy]), throwsStateError);
    }
  });

  test('平台通道按目标 URL 查询，平台错误明确向上传递', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemProxy.channel, null),
    );
    // A custom scheme avoids any proxy variables inherited by the test runner.
    messenger.setMockMethodCallHandler(SystemProxy.channel, (call) async {
      expect(call.method, 'resolve');
      expect(call.arguments, 'azusa-test://proxy.test/path');
      return ['http://127.0.0.1:7890'];
    });
    expect(
      await SystemProxy.resolve(Uri.parse('azusa-test://proxy.test/path')),
      'PROXY 127.0.0.1:7890',
    );
    messenger.setMockMethodCallHandler(SystemProxy.channel, (_) async {
      throw PlatformException(code: 'unsupported_proxy', message: '暂不支持 PAC');
    });
    await expectLater(
      SystemProxy.resolve(Uri.parse('azusa-test://proxy.test')),
      throwsA(
        isA<StateError>().having((e) => e.message, 'message', '暂不支持 PAC'),
      ),
    );
  });

  test('系统代理实际转发请求，绕过与服务开关直连', () async {
    // Widget binding replaces HttpClient with a stub; restore actual sockets
    // only inside this local-server test.
    await HttpOverrides.runWithHttpOverrides(() async {
      final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => proxy.close(force: true));
      addTearDown(() => origin.close(force: true));
      proxy.listen((request) async {
        request.response.write('proxied');
        await request.response.close();
      });
      origin.listen((request) async {
        request.response.write('direct');
        await request.response.close();
      });
      var resolutions = 0;
      Future<String> resolve(Uri uri) async {
        resolutions++;
        return uri.host == '127.0.0.1'
            ? 'DIRECT'
            : 'PROXY 127.0.0.1:${proxy.port}';
      }

      const settings = ConnectionSettings(proxyMode: ProxyMode.system);
      final dio = createServiceClient(settings, systemProxyResolver: resolve);
      final dav = createServiceClient(
        settings,
        service: NetworkService.webdav,
        systemProxyResolver: (_) async => throw StateError('不应查询系统代理'),
      );
      addTearDown(() => dio.close(force: true));
      addTearDown(() => dav.close(force: true));
      final responses = await Future.wait([
        dio.get<String>('http://example.invalid/path'),
        dio.get<String>('http://127.0.0.1:${origin.port}/path'),
      ]);
      expect(responses.map((r) => r.data), ['proxied', 'direct']);
      expect(resolutions, 2);
      expect(
        (await dav.get<String>('http://127.0.0.1:${origin.port}/')).data,
        'direct',
      );
      final failed = createServiceClient(
        settings,
        systemProxyResolver: (_) async => throw StateError('不支持的系统代理'),
      );
      addTearDown(() => failed.close(force: true));
      try {
        await failed.get<String>('http://127.0.0.1:${origin.port}/');
        fail('解析失败不得悄悄直连');
      } catch (error) {
        expect(serviceError(error), '不支持的系统代理');
      }
    }, _RealHttpOverrides());
  });
}

class _RealHttpOverrides extends HttpOverrides {}

class _MemoryPreferences implements SharedPreferencesAsync {
  final _values = <String, String>{};
  String? get raw => _values['connections'];
  set raw(String? value) {
    if (value == null) {
      _values.remove('connections');
    } else {
      _values['connections'] = value;
    }
  }

  @override
  Future<String?> getString(String key) async => raw;

  @override
  Future<void> setString(String key, String value) async {
    raw = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EmptySecrets extends FlutterSecureStorage {
  final values = <String, String>{};
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value != null) values[key] = value;
  }
}
