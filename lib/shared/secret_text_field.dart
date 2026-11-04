import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import 'text_field_action.dart';

class SecretTextField extends StatelessWidget {
  const SecretTextField({
    required this.controller,
    required this.label,
    required this.visible,
    required this.onVisibilityChange,
    required this.showLabel,
    required this.hideLabel,
    this.enabled = true,
    this.hint,
    this.fieldKey,
    this.toggleKey,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool visible;
  final ValueChanged<bool> onVisibilityChange;
  final String showLabel;
  final String hideLabel;
  final bool enabled;
  final Key? fieldKey;
  final Key? toggleKey;

  @override
  Widget build(BuildContext context) => FTextField(
    key: fieldKey,
    label: Text(label),
    hint: hint,
    enabled: enabled,
    control: .managed(controller: controller),
    obscureText: !visible,
    autocorrect: false,
    enableSuggestions: false,
    enableIMEPersonalizedLearning: false,
    suffixBuilder: (context, style, variants) => TextFieldAction(
      key: toggleKey,
      style: style,
      label: visible ? hideLabel : showLabel,
      icon: visible ? FLucideIcons.eyeOff : FLucideIcons.eye,
      onPress: enabled ? () => onVisibilityChange(!visible) : null,
    ),
  );
}
