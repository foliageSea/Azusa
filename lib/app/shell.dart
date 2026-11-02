import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;

import '../core/settings/settings.dart';
import '../core/window/desktop_window.dart';
import '../features/organizer/organizer_state.dart';
import '../shared/azusa_logo.dart';
import '../shared/widgets.dart';
import '../shared/localization.dart';

class AppShell extends ConsumerWidget {
  const AppShell({required this.shell, super.key});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(organizerProvider, (previous, next) {
      if (previous == null ||
          !(previous.busy || previous.executing) ||
          next.busy ||
          next.executing ||
          next.message.isEmpty ||
          next.hasError ||
          next.message == '下载完成') {
        return;
      }
      notifyUser(context, next.message, type: NoticeType.success);
    });
    final window = ref.watch(desktopWindowProvider);
    final organizer = ref.watch(organizerProvider);
    final settings = ref.watch(settingsProvider);
    final dark = switch (settings.themeMode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system =>
        MediaQuery.platformBrightnessOf(context) == Brightness.dark,
    };
    final l = context.l10n;
    final themeAction = dark ? l.switchLight : l.switchDark;
    final showBack =
        shell.currentIndex == 0 &&
        GoRouterState.of(context).uri.path.startsWith('/organize/assistant');
    final labels = [
      l.organizeSeries,
      l.executionHistory,
      l.aiUsage,
      l.settings,
    ];
    const icons = [
      FLucideIcons.folderPen,
      FLucideIcons.history,
      FLucideIcons.chartNoAxesCombined,
      FLucideIcons.settings2,
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = constraints.maxWidth < mobileBreakpoint;
        return ListenableBuilder(
          listenable: window,
          builder: (context, _) => Column(
            children: [
              if (window.available && !window.fullScreen)
                GestureDetector(
                  onPanStart: (_) => window.drag(),
                  onDoubleTap: window.toggleMaximize,
                  child: ColoredBox(
                    color: context.theme.colors.muted,
                    child: SizedBox(
                      height: 48,
                      child: Row(
                        children: [
                          const SizedBox(width: 20),
                          const Expanded(child: Text('Azusa')),
                          FButton.icon(
                            variant: .ghost,
                            onPress: window.minimize,
                            semanticsLabel: l.minimizeWindow,
                            child: const Icon(FLucideIcons.minus),
                          ),
                          FButton.icon(
                            variant: .ghost,
                            onPress: window.toggleMaximize,
                            semanticsLabel: l.maximizeWindow,
                            child: const Icon(FLucideIcons.square),
                          ),
                          FButton.icon(
                            variant: .ghost,
                            onPress: window.close,
                            semanticsLabel: l.close,
                            child: const Icon(FLucideIcons.x),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: ColoredBox(
                  color: context.theme.colors.muted,
                  child: Row(
                    children: [
                      if (!mobile)
                        SizedBox(
                          width: constraints.maxWidth < 1024 ? 76 : 184,
                          child: FSidebar(
                            style: .delta(
                              decoration: .value(
                                BoxDecoration(
                                  color: context.theme.colors.muted,
                                ),
                              ),
                              headerPadding: .value(EdgeInsets.zero),
                              contentPadding: .value(EdgeInsets.zero),
                            ),
                            header: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 16,
                              ),
                              child: constraints.maxWidth < 1024
                                  ? const Center(child: AzusaLogo(height: 24))
                                  : Align(
                                      alignment: Alignment.centerLeft,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const AzusaLogo(height: 24),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Azusa',
                                            style: context
                                                .theme
                                                .typography
                                                .body
                                                .lg
                                                .copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                            ),
                            children: [
                              FSidebarGroup(
                                style: .delta(
                                  padding: .value(
                                    const EdgeInsets.symmetric(horizontal: 12),
                                  ),
                                ),
                                children: [
                                  for (var i = 0; i < labels.length; i++)
                                    FSidebarItem(
                                      style: .delta(
                                        padding: .value(
                                          const EdgeInsets.all(8),
                                        ),
                                        backgroundColor: .delta([
                                          .all(
                                            shell.currentIndex == i
                                                ? context.theme.colors.primary
                                                : const Color(0x00000000),
                                          ),
                                          .exact(
                                            {.selected, .hovered, .pressed},
                                            shell.currentIndex == i
                                                ? context.theme.colors.primary
                                                : context
                                                      .theme
                                                      .colors
                                                      .background,
                                          ),
                                        ]),
                                      ),
                                      icon: Icon(
                                        icons[i],
                                        size: 20,
                                        color: shell.currentIndex == i
                                            ? context
                                                  .theme
                                                  .colors
                                                  .primaryForeground
                                            : null,
                                      ),
                                      label: constraints.maxWidth < 1024
                                          ? null
                                          : Text(
                                              labels[i],
                                              style: shell.currentIndex == i
                                                  ? TextStyle(
                                                      color: context
                                                          .theme
                                                          .colors
                                                          .primaryForeground,
                                                    )
                                                  : null,
                                            ),
                                      selected: shell.currentIndex == i,
                                      onPress: () => shell.goBranch(i),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      Expanded(
                        child: ClipRRect(
                          key: const ValueKey('route-surface'),
                          borderRadius: mobile
                              ? BorderRadius.zero
                              : const BorderRadius.only(
                                  topLeft: Radius.circular(16),
                                ),
                          child: FScaffold(
                            childPad: false,
                            header: FHeader(
                              style: .delta(
                                padding: .value(
                                  const EdgeInsets.only(top: 16, bottom: 10),
                                ),
                              ),
                              title: Align(
                                alignment: Alignment.center,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: PageContent.maxWidth,
                                  ),
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: PageContent.paddingOf(
                                        context,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        if (showBack) ...[
                                          FButton.icon(
                                            variant: .ghost,
                                            semanticsLabel: l.previousStep,
                                            onPress:
                                                organizer.busy ||
                                                    organizer.executing
                                                ? null
                                                : () => context.pop(),
                                            child: const Icon(
                                              FLucideIcons.arrowLeft,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                        Expanded(
                                          child: Text(
                                            labels[shell.currentIndex],
                                          ),
                                        ),
                                        FTooltip(
                                          tipBuilder: (_, _) =>
                                              Text(themeAction),
                                          child: FButton.icon(
                                            variant: .ghost,
                                            semanticsLabel: themeAction,
                                            onPress: () async {
                                              try {
                                                await ref
                                                    .read(
                                                      settingsProvider.notifier,
                                                    )
                                                    .update(
                                                      (value) => value.copyWith(
                                                        themeMode: dark
                                                            ? ThemeMode.light
                                                            : ThemeMode.dark,
                                                      ),
                                                    );
                                              } catch (_) {
                                                if (context.mounted) {
                                                  notifyUser(
                                                    context,
                                                    l.saveThemeFailed,
                                                    type: NoticeType.error,
                                                  );
                                                }
                                              }
                                            },
                                            child: Icon(
                                              dark
                                                  ? FLucideIcons.sun
                                                  : FLucideIcons.moon,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            footer: mobile
                                ? FBottomNavigationBar(
                                    index: shell.currentIndex,
                                    onChange: shell.goBranch,
                                    children: [
                                      for (var i = 0; i < labels.length; i++)
                                        FBottomNavigationBarItem(
                                          icon: Icon(icons[i]),
                                          label: Text(labels[i]),
                                        ),
                                    ],
                                  )
                                : null,
                            child: shell,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
