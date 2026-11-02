import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/runtime_environment.dart';
import '../../shared/localization.dart';

class RuntimeEnvironmentSection extends ConsumerWidget {
  const RuntimeEnvironmentSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final environment = ref.watch(runtimeEnvironmentProvider);
    final size = MediaQuery.sizeOf(context);
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final rows = [
      (
        'operating-system',
        l.operatingSystem,
        switch (environment.operatingSystem) {
          'android' => 'Android',
          'ios' => 'iOS',
          'macos' => 'macOS',
          'windows' => 'Windows',
          'linux' => 'Linux',
          _ => environment.operatingSystem,
        },
      ),
      ('system-version', l.systemVersion, environment.operatingSystemVersion),
      ('dart-version', l.dartVersion, environment.dartVersion),
      (
        'build-mode',
        l.buildMode,
        switch (environment.buildMode) {
          RuntimeBuildMode.debug => l.buildModeDebug,
          RuntimeBuildMode.profile => l.buildModeProfile,
          RuntimeBuildMode.release => l.buildModeRelease,
        },
      ),
      (
        'processors',
        l.processorCount,
        environment.numberOfProcessors.toString(),
      ),
      (
        'window-size',
        l.windowSize,
        '${size.width.round()} × ${size.height.round()} px',
      ),
      ('pixel-ratio', l.devicePixelRatio, '${pixelRatio.toStringAsFixed(2)}×'),
      ('system-locale', l.systemLocale, environment.systemLocale),
      (
        'app-locale',
        l.appLocale,
        Localizations.localeOf(context).toLanguageTag(),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (id, label, value) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final labelWidget = Text(
                  label,
                  style: context.theme.typography.body.sm.copyWith(
                    color: context.theme.colors.mutedForeground,
                  ),
                );
                final valueWidget = SelectableText(
                  value,
                  key: ValueKey('runtime-$id'),
                  style: context.theme.typography.body.md,
                );
                if (constraints.maxWidth >= 600 &&
                    MediaQuery.textScalerOf(context).scale(16) <= 24) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 180, child: labelWidget),
                      const SizedBox(width: 16),
                      Expanded(child: valueWidget),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    labelWidget,
                    const SizedBox(height: 4),
                    valueWidget,
                  ],
                );
              },
            ),
          ),
      ],
    );
  }
}
