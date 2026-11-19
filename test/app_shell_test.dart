import 'package:azusa/app/app.dart';
import 'package:azusa/app/router.dart';
import 'package:azusa/app/shell.dart';
import 'package:azusa/core/settings/settings.dart';
import 'package:azusa/core/window/desktop_window.dart';
import 'package:azusa/features/organizer/startup_connection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  for (final (macOS, glassSupported) in [
    (true, true),
    (true, false),
    (false, false),
  ]) {
    testWidgets('window chrome with macOS=$macOS and glass=$glassSupported', (
      tester,
    ) async {
      final window = _TestWindow(macOS: macOS);
      final router = GoRouter(
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (_, _, shell) => AppShell(shell: shell),
            branches: [
              StatefulShellBranch(
                routes: [
                  GoRoute(path: '/', builder: (_, _) => const SizedBox()),
                ],
              ),
            ],
          ),
        ],
      );
      addTearDown(window.dispose);
      addTearDown(router.dispose);
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            desktopWindowProvider.overrideWithValue(window),
            initialSettingsProvider.overrideWithValue(
              const AppSettings(themeMode: ThemeMode.light),
            ),
            routerProvider.overrideWithValue(router),
            settingsRepositoryProvider.overrideWithValue(_TestSettings()),
            startupConnectionProvider.overrideWith((_) async {}),
          ],
          child: const StarterApp(),
        ),
      );
      await tester.pumpAndSettle();

      final titleBar = find.byKey(const ValueKey('window-title-bar'));
      final sidebar = find.byType(FSidebar);
      Finder background(Color color) => find.byWidgetPredicate(
        (widget) => widget is ColoredBox && widget.color == color,
      );

      void expectChrome(Brightness brightness, {required bool translucent}) {
        final colors = FTheme.of(tester.element(sidebar)).colors;
        expect(colors.brightness, brightness);
        final chrome = translucent
            ? colors.muted.withValues(alpha: 0.12)
            : colors.muted;
        expect(
          find.ancestor(of: titleBar, matching: background(chrome)),
          findsOneWidget,
        );
        expect(
          find.ancestor(of: sidebar, matching: background(chrome)),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(FScaffold),
            matching: background(colors.background),
          ),
          findsOneWidget,
        );
      }

      expectChrome(Brightness.light, translucent: false);
      if (glassSupported) {
        window.confirmNativeGlass();
        await tester.pumpAndSettle();
        expectChrome(Brightness.light, translucent: true);
      }

      await tester.tap(find.byKey(const ValueKey('theme-toggle')));
      await tester.pumpAndSettle();
      expectChrome(Brightness.dark, translucent: glassSupported);
      expect(
        window.appearances,
        macOS ? [Brightness.light, Brightness.dark] : [],
      );

      window.enterFullScreen();
      await tester.pumpAndSettle();
      expect(titleBar, findsNothing);
      expect(
        find.ancestor(
          of: sidebar,
          matching: background(FTheme.of(tester.element(sidebar)).colors.muted),
        ),
        findsOneWidget,
      );
    });
  }
}

class _TestWindow extends DesktopWindowController {
  _TestWindow({required this.macOS});

  final appearances = <Brightness>[];
  @override
  final bool macOS;
  @override
  bool nativeGlass = false;
  @override
  bool get available => true;
  @override
  bool fullScreen = false;
  @override
  bool get focused => true;
  @override
  bool get maximized => false;

  void confirmNativeGlass() {
    nativeGlass = true;
    notifyListeners();
  }

  void enterFullScreen() {
    fullScreen = true;
    notifyListeners();
  }

  @override
  Future<void> updateAppearance(Brightness brightness) async {
    if (macOS) appearances.add(brightness);
  }

  @override
  Future<void> initialize() async {}
  @override
  Future<void> drag() async {}
  @override
  Future<void> minimize() async {}
  @override
  Future<void> toggleMaximize() async {}
  @override
  Future<void> close() async {}
}

class _TestSettings implements SettingsRepository {
  @override
  Future<AppSettings> load() async => const AppSettings();
  @override
  Future<void> save(AppSettings settings) async {}
}
