import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

/// Keep button labels inside the available width, including at large text scales.
Widget responsiveButtonContent(
  BuildContext context,
  FButtonStyle style,
  TextStyle textStyle,
  IconThemeData iconStyle,
  FCircularProgressStyle progressStyle,
  Widget? child,
) => Flexible(child: child!);
