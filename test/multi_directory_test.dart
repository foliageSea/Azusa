import 'package:azusa/features/assistant/assistant_state.dart';
import 'package:azusa/features/organizer/ai/agent.dart';
import 'package:azusa/features/organizer/ai/agent_activity.dart';
import 'package:azusa/features/organizer/ai/ai_usage.dart';
import 'package:azusa/features/organizer/ai/folder_layout.dart';
import 'package:azusa/features/organizer/connections/connection_settings.dart';
import 'package:azusa/features/organizer/dav/webdav.dart';
import 'package:azusa/features/organizer/organizer_state.dart';
import 'package:azusa/features/organizer/rename_plan.dart';
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
  _Dav(super.settings, this.calls);
  final List<String> calls;
  final listings = <String, List<DavEntry>>{};
  final failures = <String>{};

  @override
  Future<List<DavEntry>> list(String path) async {
    calls.add(path);
    if (failures.contains(path)) throw StateError('Directory unavailable');
    if (listings.containsKey(path)) return listings[path]!;
    return switch (path) {
      '/dav/' => const [DavEntry('/dav/a/', true), DavEntry('/dav/b/', true)],
      '/dav/a/' => const [
        DavEntry('/dav/a/child/', true),
        DavEntry('/dav/a/one.mkv', false),
      ],
      '/dav/a/child/' => const [DavEntry('/dav/a/child/two.mkv', false)],
      '/dav/b/' => const [DavEntry('/dav/b/three.mkv', false)],
      _ => [],
    };
  }
}

class _Agent extends RenameAgent {
  _Agent(super.settings, super.dav, super.tmdb, this.scopes);
  final List<String> scopes;

  @override
  Future<List<RenameItem>> propose(
    String directory,
    List<DavEntry> entries, {
    String instruction = '',
    FolderLayout? folderLayout,
    void Function(String message)? onStatus,
    void Function(AiUsage usage)? onUsage,
    void Function(AgentActivity activity)? onActivity,
    void Function(FolderLayout layout)? onLayout,
  }) async {
    scopes.add(directory);
    return [
      for (final entry in entries.where((e) => !e.directory))
        RenameItem(
          source: entry.path,
          targetName: 'renamed-${entry.name}',
          scope: directory,
          tmdbMediaType: TmdbMediaType.tv,
          mediaTitle: 'Show',
          seasonNumber: 1,
        ),
    ];
  }
}

void main() {
  test(
    'selection stays within the current directory and resets on navigation',
    () async {
      final dav = _Dav(
        const ConnectionSettings(webdavUrl: 'https://nas.test/dav/'),
        [],
      );
      final container = ProviderContainer(
        overrides: [
          connectionSettingsProvider.overrideWith(_Connections.new),
          webDavFactoryProvider.overrideWithValue((_) => dav),
        ],
      );
      addTearDown(container.dispose);
      await container.read(connectionSettingsProvider.future);
      final controller = container.read(organizerProvider.notifier);
      OrganizerState current() => container.read(organizerProvider);

      await controller.open('/dav/');
      controller.selectDirectories(['/dav/a/', '/dav/b/', '/dav/a/child/']);
      expect(current().selectedDirectories, ['/dav/a/', '/dav/b/']);

      // Refresh preserves valid selections, but removes deleted directories.
      final selection = current().selectedDirectories;
      await controller.open('/dav/');
      expect(current().selectedDirectories, same(selection));
      expect(current().selectedDirectories, ['/dav/a/', '/dav/b/']);
      dav.listings['/dav/'] = const [DavEntry('/dav/a/', true)];
      await controller.open('/dav/');
      expect(current().selectedDirectories, ['/dav/a/']);

      // Failed navigation keeps the current location and its selection intact.
      dav.failures.add('/dav/unavailable/');
      await controller.open('/dav/unavailable/');
      expect(current().directory, '/dav/');
      expect(current().selectedDirectories, ['/dav/a/']);

      await controller.open('/dav/a/');
      expect(current().selectedDirectories, isEmpty);
      expect(current().organizingDirectories, ['/dav/a/']);
      controller.selectDirectories([
        '/dav/b/',
        '/dav/a/one.mkv',
        '/dav/a/child/',
      ]);
      expect(current().selectedDirectories, ['/dav/a/child/']);

      await controller.open('/dav/');
      expect(current().selectedDirectories, isEmpty);
      controller.toggleDirectory('/dav/a/');
      await controller.open('/dav/b/');
      expect(current().selectedDirectories, isEmpty);
      controller.toggleDirectory('/dav/a/');
      expect(current().selectedDirectories, isEmpty);

      await controller.open(null);
      expect(current().directory, '/dav/');
      expect(current().selectedDirectories, isEmpty);
    },
  );

  test(
    'recursive scopes deduplicate ancestors without merging sibling names',
    () {
      const state = OrganizerState(
        directory: '/dav/',
        selectedDirectories: ['/dav/a/', '/dav/a/child/', '/dav/ab/'],
      );
      expect(state.organizingDirectories, ['/dav/a/', '/dav/ab/']);
      expect(
        state.copyWith(includeSubdirectories: false).organizingDirectories,
        ['/dav/a/', '/dav/a/child/', '/dav/ab/'],
      );
    },
  );

  test(
    'multiple roots scan once, keep layouts isolated and invalidate consent',
    () async {
      final calls = <String>[];
      final scopes = <String>[];
      final container = ProviderContainer(
        overrides: [
          connectionSettingsProvider.overrideWith(_Connections.new),
          modelPricingLookupProvider.overrideWithValue((_) async => null),
          webDavFactoryProvider.overrideWithValue(
            (settings) => _Dav(settings, calls),
          ),
          renameAgentFactoryProvider.overrideWithValue(
            (settings, dav, tmdb) => _Agent(settings, dav, tmdb, scopes),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(connectionSettingsProvider.future);
      final controller = container.read(organizerProvider.notifier);
      await controller.open('/dav/');
      controller.selectDirectories([
        '/dav/b',
        '/dav/a/',
        '/dav/a/child/',
        '/dav/a/',
      ]);
      expect(container.read(organizerProvider).selectedDirectories, [
        '/dav/a/',
        '/dav/b/',
      ]);
      final assistant = container.read(assistantProvider.notifier);
      assistant.grantConsent();
      expect(assistant.hasConsent, isTrue);
      calls.clear();
      await controller.propose(folderLayout: FolderLayout.full);
      final state = container.read(organizerProvider);
      expect(state.hasError, isFalse, reason: state.message);
      expect(state.plan, hasLength(3));
      expect(calls.where((path) => path == '/dav/a/child/'), hasLength(1));
      expect(scopes.toSet(), {'/dav/a/', '/dav/b/'});
      for (final item in state.plan) {
        expect(item.targetDirectory, startsWith(item.scope!));
      }
      controller.applyLayout(FolderLayout.none);
      for (final item in container.read(organizerProvider).plan) {
        if (item.parent != item.scope) expect(item.targetDirectory, item.scope);
      }
      controller.toggleDirectory('/dav/b/');
      expect(assistant.hasConsent, isFalse);
      expect(container.read(organizerProvider).plan, isEmpty);
      controller.disconnect();
      expect(container.read(organizerProvider).selectedDirectories, isEmpty);
    },
  );
}
