import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

bool get isDesktop =>
    !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

abstract class DesktopWindowController extends ChangeNotifier {
  bool get available;
  bool get macOS;
  bool get maximized;
  bool get fullScreen;
  bool get focused;
  Future<void> initialize();
  Future<void> drag();
  Future<void> minimize();
  Future<void> toggleMaximize();
  Future<void> close();
}

class NativeDesktopWindowController extends DesktopWindowController
    with WindowListener {
  @override
  bool get available => isDesktop;
  @override
  bool get macOS => Platform.isMacOS;
  bool _maximized = false, _fullScreen = false, _focused = true;
  @override
  bool get maximized => _maximized;
  @override
  bool get fullScreen => _fullScreen;
  @override
  bool get focused => _focused;
  bool _disposed = false;
  @override
  Future<void> initialize() async {
    if (!available) return;
    await windowManager.ensureInitialized();
    windowManager.addListener(this);
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(1280, 800),
        minimumSize: Size(480, 600),
        center: true,
        title: 'Azusa',
        titleBarStyle: TitleBarStyle.hidden,
        windowButtonVisibility: false,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
    await _refresh();
  }

  Future<void> _refresh() async {
    final results = await Future.wait([
      windowManager.isMaximized(),
      windowManager.isFullScreen(),
      windowManager.isFocused(),
    ]);
    if (_disposed) return;
    _maximized = results[0];
    _fullScreen = results[1];
    _focused = results[2];
    notifyListeners();
  }

  @override
  void onWindowEvent(String eventName) {
    _refresh();
  }

  @override
  Future<void> drag() => windowManager.startDragging();
  @override
  Future<void> minimize() => windowManager.minimize();
  @override
  Future<void> toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
    await _refresh();
  }

  @override
  Future<void> close() => windowManager.close();
  @override
  void dispose() {
    _disposed = true;
    if (available) windowManager.removeListener(this);
    super.dispose();
  }
}

final desktopWindowProvider = Provider<DesktopWindowController>((ref) {
  final controller = NativeDesktopWindowController();
  ref.onDispose(controller.dispose);
  return controller;
});
