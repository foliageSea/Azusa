import 'package:flutter/widgets.dart';

/// 与各平台应用图标一致的白底黑标圆角图标，不随主题重新着色。
class AzusaLogo extends StatelessWidget {
  const AzusaLogo({this.height = 32, super.key});

  final double height;
  static const assetPath = 'assets/icon/ui/icon_rounded.png';

  @override
  Widget build(BuildContext context) => Image.asset(
    assetPath,
    width: height,
    height: height,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.high,
    semanticLabel: 'Azusa',
  );
}
