import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'connection_settings.dart';
import 'system_proxy.dart';

Uri validatedHttpUrl(String value, {bool allowHttp = false}) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.query.isNotEmpty ||
      uri.fragment.isNotEmpty ||
      !(uri.scheme == 'https' || (allowHttp && uri.scheme == 'http'))) {
    throw const FormatException('请输入有效的 HTTPS 地址（WebDAV 可使用 HTTP）');
  }
  return uri;
}

enum NetworkService { ai, tmdb, webdav }

bool usesProxy(ConnectionSettings settings, NetworkService service) =>
    settings.proxyMode != ProxyMode.direct &&
    (settings.proxyMode != ProxyMode.manual ||
        settings.proxyUrl.trim().isNotEmpty) &&
    switch (service) {
      NetworkService.ai => settings.proxyAi,
      NetworkService.tmdb => settings.proxyTmdb,
      NetworkService.webdav => settings.proxyWebdav,
    };

Uri? validatedProxy(String value) {
  if (value.trim().isEmpty) return null;
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.scheme != 'http' ||
      !uri.hasPort ||
      uri.port < 1 ||
      uri.port > 65535 ||
      uri.userInfo.isNotEmpty ||
      (uri.path != '' && uri.path != '/') ||
      uri.query.isNotEmpty ||
      uri.fragment.isNotEmpty) {
    throw const FormatException('代理地址应为 http://主机:端口');
  }
  return uri;
}

Dio createServiceClient(
  ConnectionSettings settings, {
  NetworkService service = NetworkService.ai,
  Duration timeout = const Duration(seconds: 25),
  SystemProxyResolver systemProxyResolver = SystemProxy.resolve,
}) {
  final proxy = settings.proxyMode == ProxyMode.manual
      ? validatedProxy(settings.proxyUrl)
      : null;
  final dio = Dio(
    BaseOptions(
      connectTimeout: timeout,
      sendTimeout: timeout,
      receiveTimeout: timeout,
      followRedirects: false,
    ),
  );
  if (settings.proxyMode == ProxyMode.system && usesProxy(settings, service)) {
    dio.httpClientAdapter = _SystemProxyAdapter(systemProxyResolver);
    return dio;
  }
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () {
      final client = HttpClient();
      client.findProxy = (_) => proxy != null && usesProxy(settings, service)
          ? 'PROXY ${proxy.host.contains(':') ? '[${proxy.host}]' : proxy.host}:${proxy.port}'
          : 'DIRECT';
      return client;
    },
  );
  return dio;
}

/// Keep a separate client for each route: mutating a shared findProxy callback
/// would route concurrent requests through the wrong proxy.
class _SystemProxyAdapter implements HttpClientAdapter {
  _SystemProxyAdapter(this.resolve);

  final SystemProxyResolver resolve;
  final _adapters = <String, IOHttpClientAdapter>{};
  bool _closed = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (_closed) throw StateError('网络客户端已关闭');
    final timeout = options.connectTimeout;
    final resolution = resolve(options.uri);
    final route = await (timeout != null && timeout > Duration.zero
        ? resolution.timeout(
            timeout,
            onTimeout: () => throw StateError('读取系统代理超时'),
          )
        : resolution);
    if (_closed) throw StateError('网络客户端已关闭');
    final adapter = _adapters.putIfAbsent(
      route,
      () => IOHttpClientAdapter(
        createHttpClient: () => HttpClient()..findProxy = (_) => route,
      ),
    );
    return adapter.fetch(options, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) {
    _closed = true;
    for (final adapter in _adapters.values) {
      adapter.close(force: force);
    }
    _adapters.clear();
  }
}

String serviceError(Object error) {
  if (error is DioException) {
    if (error.error is StateError) return serviceError(error.error!);
    final code = error.response?.statusCode;
    if (code == 401 || code == 403) return '认证失败或没有访问权限（HTTP $code）';
    if (code == 407) return '代理要求认证，当前仅支持无认证 HTTP 代理';
    if (code == 412) return '文件已变化或目标已存在，请刷新目录核对';
    if (code == 429) return '请求过于频繁，请稍后再试';
    return code == null ? '网络连接失败或超时，请检查服务地址与 HTTP 代理' : '服务返回 HTTP $code';
  }
  if (error is FormatException) return error.message;
  if (error is StateError) return error.message.toString();
  return '操作失败，请重试';
}
