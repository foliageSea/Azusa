import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import 'icon_action.dart';

/// A trailing icon action without a button surface or an exterior focus ring.
class TextFieldAction extends StatelessWidget {
  const TextFieldAction({
    required this.style,
    required this.label,
    required this.icon,
    required this.onPress,
    this.loading = false,
    super.key,
  });

  final FTextFieldStyle style;
  final String label;
  final IconData icon;
  final VoidCallback? onPress;
  final bool loading;

  @override
  Widget build(BuildContext context) => Padding(
    padding: style.obscureButtonPadding,
    child: IconAction(
      label: label,
      icon: icon,
      loading: loading,
      onPress: onPress,
    ),
  );
}
