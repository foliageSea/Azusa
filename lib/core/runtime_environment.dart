import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final runtimeEnvironmentProvider = Provider(
  (ref) => RuntimeEnvironment.fromPlatform(),
);

enum RuntimeBuildMode { debug, profile, release }

class RuntimeEnvironment {
  const RuntimeEnvironment({
    required this.operatingSystem,
    required this.operatingSystemVersion,
    required this.dartVersion,
    required this.buildMode,
    required this.numberOfProcessors,
    required this.systemLocale,
  });

  factory RuntimeEnvironment.fromPlatform() => RuntimeEnvironment(
    operatingSystem: Platform.operatingSystem,
    operatingSystemVersion: Platform.operatingSystemVersion,
    dartVersion: Platform.version,
    buildMode: kReleaseMode
        ? RuntimeBuildMode.release
        : kProfileMode
        ? RuntimeBuildMode.profile
        : RuntimeBuildMode.debug,
    numberOfProcessors: Platform.numberOfProcessors,
    systemLocale: Platform.localeName,
  );

  final String operatingSystem;
  final String operatingSystemVersion;
  final String dartVersion;
  final RuntimeBuildMode buildMode;
  final int numberOfProcessors;
  final String systemLocale;
}
