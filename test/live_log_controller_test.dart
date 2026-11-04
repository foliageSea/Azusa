import 'package:azusa/core/logging/live_log_store.dart';
import 'package:azusa/features/settings/live_log_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

void main() {
  test('区分空日志和筛选无结果，重置筛选不改变暂停或清空视图边界', () {
    final store = LiveLogStore();
    addTearDown(store.dispose);
    store.add(level: Level.INFO, time: DateTime.now(), text: 'entry');
    final controller = LiveLogController(store);
    addTearDown(controller.dispose);
    controller.togglePaused();
    controller.setQuery('missing');
    controller.setMinimumLevel(Level.SEVERE);
    expect(controller.entries, isEmpty);
    expect(controller.hasUnfilteredEntries, isTrue);
    expect(controller.hasFilters, isTrue);
    controller.clearFilters();
    expect(controller.entries.single.text, 'entry');
    expect(controller.minimumLevel, Level.ALL);
    expect(controller.paused, isTrue);
    expect(controller.hasFilters, isFalse);
    expect(store.snapshot, hasLength(1));
    controller.clearView();
    controller.setQuery('entry');
    controller.clearFilters();
    expect(controller.entries, isEmpty);
    expect(controller.hasUnfilteredEntries, isFalse);
    expect(store.snapshot, hasLength(1));
  });
}
