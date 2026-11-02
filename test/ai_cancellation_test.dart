import 'dart:async';

import 'package:azusa/features/organizer/connections/connection_settings.dart';
import 'package:azusa/features/organizer/dav/webdav.dart';
import 'package:azusa/features/organizer/organizer_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Connections extends ConnectionSettingsController {
  @override
  Future<ConnectionSettings> build() async => const ConnectionSettings(
    webdavUrl: 'https://nas.test/dav/',
    model: 'test',
  );
}

class _Dav extends WebDavClient {
  _Dav(super.settings);
  final pending = Completer<List<DavEntry>>();
  var calls = 0;
  var closed = false;
  @override
  Future<List<DavEntry>> list(String path) {
    if (++calls == 1) return Future.value([]);
    return pending.future;
  }

  @override
  void close() {
    closed = true;
    super.close();
  }
}

void main() {
  test('扫描期间中断立即解除锁定，迟到结果不覆盖新目录，可再次操作', () async {
    late _Dav scanning;
    var clients = 0;
    final container = ProviderContainer(
      overrides: [
        connectionSettingsProvider.overrideWith(_Connections.new),
        modelPricingLookupProvider.overrideWithValue((_) async => null),
        webDavFactoryProvider.overrideWithValue((settings) {
          final dav = _Dav(settings);
          if (++clients == 2) {
            scanning = dav;
            dav.calls = 1;
          }
          return dav;
        }),
      ],
    );
    addTearDown(container.dispose);
    await container.read(connectionSettingsProvider.future);
    final controller = container.read(organizerProvider.notifier);
    await controller.open('/dav/');
    final task = controller.propose();
    expect(container.read(organizerProvider).analyzing, isTrue);
    controller.cancelSuggestions();
    controller.cancelSuggestions();
    await task.timeout(const Duration(seconds: 1));
    expect(scanning.closed, isTrue);
    expect(container.read(organizerProvider).busy, isFalse);
    expect(container.read(organizerProvider).analyzing, isFalse);
    expect(container.read(organizerProvider).message, 'AI 建议已中断');
    expect(container.read(organizerProvider).plan, isEmpty);
    await controller.open('/dav/new/');
    scanning.pending.complete([const DavEntry('/dav/stale.mkv', false)]);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(organizerProvider).directory, '/dav/new/');
    expect(container.read(organizerProvider).message, isEmpty);
    expect(container.read(organizerProvider).entries, isEmpty);
  });
}
