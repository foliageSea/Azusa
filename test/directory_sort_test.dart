import 'package:azusa/core/settings/directory_sort.dart';
import 'package:azusa/core/settings/settings.dart';
import 'package:azusa/features/organizer/dav/directory_sort.dart';
import 'package:azusa/features/organizer/dav/webdav.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Test-only in-memory backend for the shared_preferences dependency.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';

void main() {
  const entries = [
    DavEntry(
      '/dav/b.mkv',
      false,
      size: 10,
      modified: 'Wed, 01 Jan 2025 00:00:00 GMT',
    ),
    DavEntry('/dav/a.mkv', false, size: 20, modified: '2026-01-01T00:00:00Z'),
    DavEntry('/dav/z/', true),
    DavEntry('/dav/c.mkv', false, modified: 'invalid'),
  ];
  final expected = {
    DirectorySort.nameAscending: ['z', 'a.mkv', 'b.mkv', 'c.mkv'],
    DirectorySort.nameDescending: ['z', 'c.mkv', 'b.mkv', 'a.mkv'],
    DirectorySort.modifiedAscending: ['z', 'b.mkv', 'a.mkv', 'c.mkv'],
    DirectorySort.modifiedDescending: ['z', 'a.mkv', 'b.mkv', 'c.mkv'],
    DirectorySort.sizeAscending: ['z', 'b.mkv', 'a.mkv', 'c.mkv'],
    DirectorySort.sizeDescending: ['z', 'a.mkv', 'b.mkv', 'c.mkv'],
  };
  for (final order in DirectorySort.values) {
    test('${order.name} 文件夹优先，未知属性在最后，原列表不变', () {
      expect(
        sortDirectoryEntries(entries, order).map((e) => e.name),
        expected[order],
      );
      expect(entries.first.name, 'b.mkv');
    });
  }

  test('同值按名称排序，大小写同名用路径确定稳定顺序', () {
    const values = [
      DavEntry('/dav/b.mkv', false, size: 1),
      DavEntry('/dav/a.mkv', false, size: 1),
      DavEntry('/dav/A.mkv', false, size: 1),
    ];
    expect(
      sortDirectoryEntries(
        values,
        DirectorySort.sizeDescending,
      ).map((e) => e.name),
      ['A.mkv', 'a.mkv', 'b.mkv'],
    );
  });

  test('旧配置和无效排序回退到名称升序', () {
    for (final value in [null, 'invalid', 42]) {
      expect(
        AppSettings.fromJson({'directorySort': value}).directorySort,
        DirectorySort.nameAscending,
      );
    }
    expect(AppSettings.fromJson({}).directorySort, DirectorySort.nameAscending);
  });

  test('全部排序模式保存后可重新加载，其他设置不丢失', () async {
    final previous = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    addTearDown(() => SharedPreferencesAsyncPlatform.instance = previous);
    final repository = PreferencesSettingsRepository(SharedPreferencesAsync());
    var container = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
    );
    for (final order in DirectorySort.values) {
      await container
          .read(settingsProvider.notifier)
          .update(
            (settings) =>
                settings.copyWith(directorySort: order, language: 'en'),
          );
      container.dispose();
      final loaded = await repository.load();
      container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(repository),
          initialSettingsProvider.overrideWithValue(loaded),
        ],
      );
      expect(container.read(settingsProvider).directorySort, order);
      expect(container.read(settingsProvider).language, 'en');
    }
    container.dispose();
  });
}
