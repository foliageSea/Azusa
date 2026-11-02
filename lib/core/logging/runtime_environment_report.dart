import 'dart:ui';

import 'package:package_info_plus/package_info_plus.dart';

import '../runtime_environment.dart';

class RuntimeEnvironmentReport {
  const RuntimeEnvironmentReport({
    required this.environment,
    this.appVersion,
    this.buildNumber,
    this.windowSize,
    this.devicePixelRatio,
    this.appLocale,
  });

  final RuntimeEnvironment environment;
  final String? appVersion;
  final String? buildNumber;
  final Size? windowSize;
  final double? devicePixelRatio;
  final String? appLocale;

  static Future<RuntimeEnvironmentReport> collect({
    RuntimeEnvironment? environment,
    Size? windowSize,
    double? devicePixelRatio,
    String? appLocale,
    Future<PackageInfo> Function()? packageInfo,
  }) async {
    final runtime = environment ?? RuntimeEnvironment.fromPlatform();
    PackageInfo? info;
    try {
      info = await (packageInfo ?? PackageInfo.fromPlatform)();
    } catch (_) {
      // Unavailable package metadata must not prevent exporting the logs.
    }
    return RuntimeEnvironmentReport(
      environment: runtime,
      appVersion: info?.version,
      buildNumber: info?.buildNumber,
      windowSize: windowSize,
      devicePixelRatio: devicePixelRatio,
      appLocale: appLocale,
    );
  }

  String toText({required DateTime exportedAt}) {
    const unavailable = 'Unavailable';
    final size = windowSize;
    return [
      'Exported at: ${exportedAt.toUtc().toIso8601String()}',
      'App version: ${appVersion ?? unavailable}',
      'Build number: ${buildNumber ?? unavailable}',
      'Operating system: ${environment.operatingSystem}',
      'System version: ${environment.operatingSystemVersion}',
      'Dart version: ${environment.dartVersion}',
      'Build mode: ${environment.buildMode.name}',
      'Processor count: ${environment.numberOfProcessors}',
      'Window size: ${size == null ? unavailable : '${size.width.round()} × ${size.height.round()} logical px'}',
      'Device pixel ratio: ${devicePixelRatio?.toStringAsFixed(2) ?? unavailable}',
      'System locale: ${environment.systemLocale}',
      'App locale: ${appLocale ?? unavailable}',
      '',
    ].join('\n');
  }
}
