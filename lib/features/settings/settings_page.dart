import '../../shared/responsive_button.dart';

import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/logging/log_export_service.dart';
import '../../core/logging/runtime_environment_report.dart';
import '../../core/runtime_environment.dart';
import '../../core/settings/settings.dart';
import '../../app/text_scaler.dart';
import '../../app/theme.dart';
import '../../shared/azusa_logo.dart';
import '../../shared/language_options.dart';
import '../../shared/localization.dart';
import '../../shared/widgets.dart';
import 'runtime_environment_section.dart';
import 'live_logs_section.dart';

const _misansLicenseUrl = 'https://hyperos.mi.com/font/download';
const _showDiagnostics = false;

final packageInfoProvider = FutureProvider((ref) => PackageInfo.fromPlatform());

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({this.connectionTabs = const [], super.key});

  final List<FTabEntry> connectionTabs;
  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  Object? _error;
  bool _saving = false;
  bool _exportingLogs = false;
  bool _logExportFailed = false;
  LogExportResult? _logExportResult;
  int _settingsTab = 0;

  Future<void> _showFontNotice(BuildContext context) {
    final l = context.l10n;
    return showFDialog<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (context, style, animation) => FDialog(
        animation: animation,
        builder: (context, style) => SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.fonts,
                style: context.theme.typography.body.lg.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l.fontNotice,
                style: context.theme.typography.body.sm.copyWith(
                  color: context.theme.colors.mutedForeground,
                ),
              ),
              const SizedBox(height: 8),
              FButton(
                key: const ValueKey('font-license-link'),
                builder: responsiveButtonContent,
                variant: .ghost,
                onPress: () => openDocumentation(context, _misansLicenseUrl),
                suffix: const Icon(FLucideIcons.externalLink),
                child: Text(_misansLicenseUrl),
              ),
              const SizedBox(height: 20),
              FButton(
                builder: responsiveButtonContent,
                variant: .outline,
                onPress: () => Navigator.of(context).pop(),
                child: Text(l.close),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportLogs(BuildContext buttonContext) async {
    if (_exportingLogs) return;
    final box = buttonContext.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() {
      _exportingLogs = true;
      _logExportFailed = false;
      _logExportResult = null;
    });
    try {
      final exporter = ref.read(logExportServiceProvider);
      final report = await RuntimeEnvironmentReport.collect(
        environment: ref.read(runtimeEnvironmentProvider),
        windowSize: MediaQuery.sizeOf(context),
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        appLocale: Localizations.localeOf(context).toLanguageTag(),
        packageInfo: () => ref.read(packageInfoProvider.future),
      );
      final result = await exporter.export(
        sharePositionOrigin: origin,
        environmentReport: report,
      );
      if (mounted) setState(() => _logExportResult = result);
    } catch (_) {
      if (mounted) setState(() => _logExportFailed = true);
    } finally {
      if (mounted) setState(() => _exportingLogs = false);
    }
  }

  Future<void> _update(AppSettings Function(AppSettings) change) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(settingsProvider.notifier).update(change);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _fillTab(Widget child) => LayoutBuilder(
    builder: (context, constraints) {
      final minHeight = MediaQuery.textScalerOf(context).scale(640);
      return SingleChildScrollView(
        child: SizedBox(
          height: constraints.maxHeight < minHeight
              ? minHeight
              : constraints.maxHeight,
          child: child,
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final settings = ref.watch(settingsProvider);
    final fontPercent =
        (resolveFontScale(
                  settings.fontScale,
                  MediaQuery.devicePixelRatioOf(context),
                ) *
                100)
            .round();
    final options = languageOptions(context);
    Widget tab(Widget child) => SingleChildScrollView(child: child);
    return PageContent(
      fill: true,
      children: [
        if (_error != null) ...[
          ErrorNotice(_error!),
          const SizedBox(height: 16),
        ],
        Expanded(
          child: _SettingsTabs(
            key: const ValueKey('settings-tabs'),
            control: FTabControl.lifted(
              index: _settingsTab,
              onChange: (index) => setState(() => _settingsTab = index),
            ),
            children: [
              FTabEntry(
                label: Text(l.general),
                child: tab(
                  Surface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 240),
                            child: FSelect<String>.rich(
                              key: const ValueKey('language-select'),
                              label: Text(l.language),
                              enabled: !_saving,
                              format: (value) => options
                                  .firstWhere((option) => option.$1 == value)
                                  .$2,
                              control: .lifted(
                                value: settings.language,
                                onChange: (value) {
                                  if (value != null &&
                                      value != settings.language) {
                                    _update((s) => s.copyWith(language: value));
                                  }
                                },
                              ),
                              children: [
                                for (final (value, label) in options)
                                  FSelectItem(title: Text(label), value: value),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              FTabEntry(
                label: Text(l.appearance),
                child: tab(
                  Surface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(l.theme),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final (i, value) in ThemeMode.values.indexed)
                              FButton(
                                builder: responsiveButtonContent,
                                mainAxisSize: MainAxisSize.min,
                                variant: settings.themeMode == value
                                    ? .primary
                                    : .outline,
                                selected: settings.themeMode == value,
                                onPress: _saving
                                    ? null
                                    : () => _update(
                                        (s) => s.copyWith(themeMode: value),
                                      ),
                                child: Text([l.system, l.light, l.dark][i]),
                              ),
                          ],
                        ),
                        const SizedBox(height: 28),
                        Text(l.themeColor),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final color in AppThemeColor.values)
                              FButton(
                                key: ValueKey('theme-color-${color.name}'),
                                builder: responsiveButtonContent,
                                mainAxisSize: MainAxisSize.min,
                                variant: settings.themeColor == color
                                    ? .primary
                                    : .outline,
                                selected: settings.themeColor == color,
                                onPress: _saving
                                    ? null
                                    : () => _update(
                                        (s) => s.copyWith(themeColor: color),
                                      ),
                                prefix: Container(
                                  width: 16,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: color.primary(
                                      context.theme.colors.brightness,
                                    ),
                                    border: Border.all(
                                      color: settings.themeColor == color
                                          ? context
                                                .theme
                                                .colors
                                                .primaryForeground
                                          : context.theme.colors.border,
                                    ),
                                  ),
                                ),
                                child: Text(switch (color) {
                                  AppThemeColor.azusa => 'Azusa',
                                  AppThemeColor.neutral => l.colorNeutral,
                                  AppThemeColor.blue => l.colorBlue,
                                  AppThemeColor.green => l.colorGreen,
                                  AppThemeColor.violet => l.colorViolet,
                                  AppThemeColor.orange => l.colorOrange,
                                  AppThemeColor.rose => l.colorRose,
                                }),
                              ),
                          ],
                        ),
                        const SizedBox(height: 28),
                        Text(l.radiusScale),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final radius in [0.0, 0.5, 1.0, 1.5, 2.0])
                              FButton(
                                key: ValueKey('radius-scale-$radius'),
                                builder: responsiveButtonContent,
                                mainAxisSize: MainAxisSize.min,
                                variant: settings.radiusScale == radius
                                    ? .primary
                                    : .outline,
                                selected: settings.radiusScale == radius,
                                onPress: _saving
                                    ? null
                                    : () => _update(
                                        (s) => s.copyWith(radiusScale: radius),
                                      ),
                                child: Text(
                                  '${radius.toStringAsFixed(radius % 1 == 0 ? 0 : 1)}×',
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 28),
                        Text(l.fontSize),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final (scale, label) in [
                              (0.8, l.fontSizeSmall),
                              (1.0, l.fontSizeStandard),
                              (1.2, l.fontSizeLarge),
                            ])
                              FButton(
                                key: ValueKey('font-scale-$scale'),
                                builder: responsiveButtonContent,
                                mainAxisSize: MainAxisSize.min,
                                variant: settings.fontScale == scale
                                    ? .primary
                                    : .outline,
                                selected: settings.fontScale == scale,
                                onPress: _saving
                                    ? null
                                    : () => _update(
                                        (s) => s.copyWith(fontScale: scale),
                                      ),
                                child: Text(label),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          key: const ValueKey('font-size-preview'),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: context.theme.colors.muted,
                            borderRadius: context.theme.style.borderRadius.md,
                            border: Border.all(
                              color: context.theme.colors.border,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${l.fontSizePreview} ($fontPercent%)',
                                style: context.theme.typography.body.sm
                                    .copyWith(
                                      color:
                                          context.theme.colors.mutedForeground,
                                    ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                l.sampleText,
                                style: context.theme.typography.body.md,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              ...widget.connectionTabs.map(
                (entry) =>
                    FTabEntry(label: entry.label, child: tab(entry.child)),
              ),
              if (_showDiagnostics)
                FTabEntry(
                  label: Text(l.logs),
                  child: _fillTab(
                    Surface(
                      expand: true,
                      padding: MediaQuery.sizeOf(context).width < 480 ? 12 : 24,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Builder(
                            builder: (buttonContext) => FButton(
                              key: const ValueKey('export-logs'),
                              builder: responsiveButtonContent,
                              variant: .outline,
                              prefix: const Icon(FLucideIcons.download),
                              onPress: _exportingLogs
                                  ? null
                                  : () => _exportLogs(buttonContext),
                              child: Text(
                                _exportingLogs ? l.exportingLogs : l.exportLogs,
                              ),
                            ),
                          ),
                          if (_logExportFailed) ...[
                            const SizedBox(height: 16),
                            FAlert(
                              variant: .destructive,
                              title: Text(l.logExportError),
                            ),
                          ],
                          if (_logExportResult != null &&
                              _logExportResult !=
                                  LogExportResult.cancelled) ...[
                            const SizedBox(height: 16),
                            Text(switch (_logExportResult!) {
                              LogExportResult.empty => l.noLogsToExport,
                              LogExportResult.saved => l.logsExported,
                              LogExportResult.shared => l.logsShared,
                              LogExportResult.presented => l.logShareOpened,
                              LogExportResult.cancelled => '',
                            }),
                          ],
                          const Expanded(child: LiveLogsSection(fill: true)),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_showDiagnostics)
                FTabEntry(
                  label: Text(l.runtimeEnvironment),
                  child: tab(const Surface(child: RuntimeEnvironmentSection())),
                ),
              if (_showDiagnostics)
                FTabEntry(
                  label: Text(l.about),
                  child: tab(
                    Surface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ref
                              .watch(packageInfoProvider)
                              .when(
                                data: (info) => Text(
                                  '${l.version} ${info.version} (${info.buildNumber})',
                                ),
                                loading: () => Text(l.loading),
                                error: (e, _) => ErrorNotice(
                                  e,
                                  onRetry: () =>
                                      ref.invalidate(packageInfoProvider),
                                ),
                              ),
                          const SizedBox(height: 16),
                          FButton(
                            builder: responsiveButtonContent,
                            mainAxisSize: MainAxisSize.min,
                            variant: .outline,
                            onPress: () => openDocumentation(
                              context,
                              'https://forui.dev/docs',
                            ),
                            suffix: const Icon(FLucideIcons.externalLink),
                            child: Text(l.openDocs),
                          ),
                          const SizedBox(height: 28),
                          FButton(
                            key: const ValueKey('font-notice'),
                            builder: responsiveButtonContent,
                            variant: .outline,
                            prefix: const Icon(FLucideIcons.type),
                            onPress: () => _showFontNotice(context),
                            child: Text(l.fonts),
                          ),
                          const SizedBox(height: 12),
                          FButton(
                            key: const ValueKey('open-source-licenses'),
                            builder: responsiveButtonContent,
                            variant: .outline,
                            prefix: const Icon(FLucideIcons.scrollText),
                            onPress: () => showLicensePage(
                              context: context,
                              applicationName: l.appTitle,
                              applicationIcon: const Padding(
                                padding: EdgeInsets.all(12),
                                child: AzusaLogo(height: 64),
                              ),
                              applicationVersion: ref
                                  .read(packageInfoProvider)
                                  .asData
                                  ?.value
                                  .version,
                            ),
                            child: Text(l.openSourceLicenses),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsTabs extends StatelessWidget {
  const _SettingsTabs({
    required this.control,
    required this.children,
    super.key,
  });

  final FTabControl control;
  final List<FTabEntry> children;

  @override
  Widget build(BuildContext context) {
    final scrollBehavior = ScrollConfiguration.of(context);
    return ScrollConfiguration(
      behavior: scrollBehavior.copyWith(
        dragDevices: {...scrollBehavior.dragDevices, PointerDeviceKind.mouse},
      ),
      child: FTabs(
        scrollable: true,
        expands: true,
        contentPhysics: switch (defaultTargetPlatform) {
          TargetPlatform.macOS ||
          TargetPlatform.windows ||
          TargetPlatform.linux => const NeverScrollableScrollPhysics(),
          _ => const BouncingScrollPhysics(),
        },
        control: control,
        children: [
          for (final entry in children)
            FTabEntry(
              label: entry.label,
              child: ScrollConfiguration(
                behavior: scrollBehavior,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: entry.child,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
