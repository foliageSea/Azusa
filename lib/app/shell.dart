import 'package:flutter/services.dart';
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

class _MacWindowControls extends StatefulWidget {
  const _MacWindowControls({required this.window});

  final DesktopWindowController window;

  @override
  State<_MacWindowControls> createState() => _MacWindowControlsState();
}

class _MacWindowControlsState extends State<_MacWindowControls> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: MouseRegion(
        onEnter: (_) => setState(() => hovered = true),
        onExit: (_) => setState(() => hovered = false),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MacWindowButton(
              key: const ValueKey('mac-close'),
              label: l.close,
              color: const Color(0xffff5f57),
              symbol: FLucideIcons.x,
              showSymbol: hovered,
              onPressed: widget.window.close,
            ),
            _MacWindowButton(
              key: const ValueKey('mac-minimize'),
              label: l.minimizeWindow,
              color: const Color(0xffffbd2e),
              symbol: FLucideIcons.minus,
              showSymbol: hovered,
              onPressed: widget.window.minimize,
            ),
            _MacWindowButton(
              key: const ValueKey('mac-maximize'),
              label: l.maximizeWindow,
              color: const Color(0xff28c840),
              symbol: FLucideIcons.chevronsUpDown,
              showSymbol: hovered,
              onPressed: widget.window.toggleMaximize,
            ),
          ],
        ),
      ),
    );
  }
}

class _MacWindowButton extends StatelessWidget {
  const _MacWindowButton({
    required this.label,
    required this.color,
    required this.symbol,
    required this.showSymbol,
    required this.onPressed,
    super.key,
  });

  final String label;
  final Color color;
  final IconData symbol;
  final bool showSymbol;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    void invoke() {
      onPressed().catchError((Object error) {
        if (context.mounted) {
          notifyUser(context, failureMessage(context, error));
        }
      });
    }

    return Semantics(
      button: true,
      label: label,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.basic,
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              invoke();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: invoke,
          child: SizedBox(
            width: 20,
            height: 24,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: SizedBox(
                  width: 12,
                  height: 12,
                  child: AnimatedOpacity(
                    opacity: showSymbol ? 1 : 0,
                    duration: const Duration(milliseconds: 100),
                    child: symbol == FLucideIcons.chevronsUpDown
                        ? CustomPaint(painter: _MacMaximizeSymbol())
                        : Icon(symbol, size: 9, color: const Color(0xff503000)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MacMaximizeSymbol extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xff006500);
    final path = Path()
      ..moveTo(3, 3)
      ..lineTo(8, 3)
      ..lineTo(3, 8)
      ..close()
      ..moveTo(9, 9)
      ..lineTo(4, 9)
      ..lineTo(9, 4)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MacMaximizeSymbol oldDelegate) => false;
}

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
    final themeToggle = FTooltip(
      tipBuilder: (_, _) => Text(themeAction),
      child: FButton.icon(
        key: const ValueKey('theme-toggle'),
        variant: .ghost,
        semanticsLabel: themeAction,
        onPress: () async {
          try {
            await ref
                .read(settingsProvider.notifier)
                .update(
                  (value) => value.copyWith(
                    themeMode: dark ? ThemeMode.light : ThemeMode.dark,
                  ),
                );
          } catch (_) {
            if (context.mounted) {
              notifyUser(context, l.saveThemeFailed, type: NoticeType.error);
            }
          }
        },
        child: Icon(dark ? FLucideIcons.sun : FLucideIcons.moon),
      ),
    );
    final showBack =
        shell.currentIndex == 1 &&
        GoRouterState.of(context).uri.path.startsWith('/organize/assistant');
    final labels = [
      l.assistantTab,
      l.filesTab,
      l.executionHistory,
      l.aiUsage,
      l.settings,
    ];
    const icons = [
      FLucideIcons.botMessageSquare,
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
                ColoredBox(
                  color: context.theme.colors.muted,
                  child: SizedBox(
                    key: const ValueKey('window-title-bar'),
                    height: 48,
                    child: Row(
                      children: [
                        if (window.macOS) _MacWindowControls(window: window),
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanStart: (_) => window.drag(),
                            onDoubleTap: window.toggleMaximize,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 20),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Azusa',
                                  style: TextStyle(
                                    color: window.focused
                                        ? context.theme.colors.foreground
                                        : context.theme.colors.mutedForeground,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: themeToggle,
                        ),
                        if (!window.macOS) ...[
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
                      ],
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
                                        size: 16,
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
                                              style: context
                                                  .theme
                                                  .typography
                                                  .body
                                                  .sm
                                                  .copyWith(
                                                    color:
                                                        shell.currentIndex == i
                                                        ? context
                                                              .theme
                                                              .colors
                                                              .primaryForeground
                                                        : context
                                                              .theme
                                                              .colors
                                                              .foreground,
                                                  ),
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
                                        if (!window.available ||
                                            window.fullScreen)
                                          themeToggle,
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
