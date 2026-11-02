import 'package:azusa/shared/azusa_logo.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('圆角图标提供 1x 到 4x 高清资源', (tester) async {
    const asset = AssetImage(AzusaLogo.assetPath);
    for (final ratio in [1.0, 2.0, 3.0, 4.0]) {
      final key = await asset.obtainKey(
        ImageConfiguration(devicePixelRatio: ratio),
      );
      expect(key.scale, ratio);
      expect(
        key.name,
        ratio == 1
            ? AzusaLogo.assetPath
            : 'assets/icon/ui/${ratio.toStringAsFixed(1)}x/icon_rounded.png',
      );
    }
  });

  testWidgets('品牌标识使用完整圆角图标且不着色', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: IconTheme(
            data: IconThemeData(color: Color(0xFFFFFFFF)),
            child: AzusaLogo(height: 36),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName, AzusaLogo.assetPath);
    expect(image.color, isNull);
    expect(tester.getSize(find.byType(Image)), const Size(36, 36));
    expect(tester.takeException(), isNull);
  });
}
