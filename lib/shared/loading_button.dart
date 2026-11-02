import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

class LoadingButton extends StatelessWidget {
  const LoadingButton({
    required this.label,
    required this.onPress,
    this.loading = false,
    this.variant = FButtonVariant.primary,
    super.key,
  });

  final String label;
  final VoidCallback? onPress;
  final bool loading;
  final FButtonVariant variant;

  @override
  Widget build(BuildContext context) => FButton(
    variant: variant,
    onPress: loading ? null : onPress,
    prefix: loading ? const FCircularProgress(size: .sm) : null,
    child: Text(label),
  );
}
