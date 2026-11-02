import 'dart:io';

import 'package:flutter/services.dart';

typedef SystemProxyResolver = Future<String> Function(Uri uri);

/// Resolves each destination independently so bypass rules remain effective.
class SystemProxy {
  static const channel = MethodChannel('azusa/system_proxy');

  static Future<String> resolve(Uri uri) async {
    if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
      final fromEnvironment = environmentProxy(uri, Platform.environment);
      if (fromEnvironment != null) return fromEnvironment;
    }
    try {
      final proxies = await channel.invokeListMethod<String>(
        'resolve',
        uri.toString(),
      );
      if (proxies == null || proxies.isEmpty) {
        throw StateError('系统代理未返回有效配置');
      }
      return normalize(proxies);
    } on MissingPluginException {
      throw StateError('当前平台不支持读取系统代理');
    } on PlatformException catch (error) {
      throw StateError(error.message ?? '读取系统代理失败');
    }
  }

  /// null means that no environment proxy was configured for this scheme.
  static String? environmentProxy(Uri uri, Map<String, String> environment) {
    final key = '${uri.scheme}_proxy';
    final value = environment[key] ?? environment[key.toUpperCase()];
    if (value == null || value.trim().isEmpty) return null;
    final proxy = Uri.tryParse(
      value.contains('://') ? value.trim() : 'http://${value.trim()}',
    );
    if (proxy == null ||
        proxy.scheme != 'http' ||
        proxy.host.isEmpty ||
        proxy.userInfo.isNotEmpty ||
        (proxy.hasPort && (proxy.port < 1 || proxy.port > 65535)) ||
        (proxy.path.isNotEmpty && proxy.path != '/') ||
        proxy.hasQuery ||
        proxy.hasFragment) {
      throw StateError('系统环境代理仅支持无认证 HTTP 代理');
    }
    final variables = Map<String, String>.of(environment);
    // Dart's resolver expects host:port, not a URL with a scheme.
    variables[key] = proxy.hasPort
        ? proxy.authority
        : '${proxy.authority}:1080';
    return HttpClient.findProxyFromEnvironment(uri, environment: variables);
  }

  static String normalize(List<String> proxies) {
    final routes = <String>[];
    for (final value in proxies) {
      final uri = Uri.tryParse(value);
      if (uri?.scheme == 'direct') {
        routes.add('DIRECT');
      } else if (uri != null &&
          uri.scheme == 'http' &&
          uri.host.isNotEmpty &&
          uri.hasPort &&
          uri.port > 0 &&
          uri.port <= 65535 &&
          uri.userInfo.isEmpty) {
        routes.add('PROXY ${uri.authority}');
      } else {
        throw StateError('系统代理包含不支持的类型，仅支持无认证 HTTP 代理');
      }
    }
    if (routes.isEmpty) throw StateError('系统代理未返回有效配置');
    return routes.join('; ');
  }
}
