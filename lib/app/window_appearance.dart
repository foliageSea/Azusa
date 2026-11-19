import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/window/desktop_window.dart';

class WindowAppearance extends StatefulWidget {
  const WindowAppearance({
    required this.controller,
    required this.brightness,
    required this.child,
    super.key,
  });

  final DesktopWindowController controller;
  final Brightness brightness;
  final Widget child;

  @override
  State<WindowAppearance> createState() => _WindowAppearanceState();
}

class _WindowAppearanceState extends State<WindowAppearance> {
  @override
  void initState() {
    super.initState();
    _syncAppearance();
  }

  @override
  void didUpdateWidget(WindowAppearance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.brightness != widget.brightness) {
      _syncAppearance();
    }
  }

  void _syncAppearance() =>
      unawaited(widget.controller.updateAppearance(widget.brightness));

  @override
  Widget build(BuildContext context) => widget.child;
}
