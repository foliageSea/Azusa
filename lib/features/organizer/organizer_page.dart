import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets.dart';
import '../../core/settings/settings.dart';
import '../../core/settings/directory_sort.dart';
import '../../shared/localization.dart';
import '../../shared/runtime_localization.dart';
import '../../shared/responsive_button.dart';
import 'connections/connection_settings.dart';
import 'dav/dav_paths.dart';
import 'dav/directory_breadcrumb.dart';
import 'dav/directory_sort.dart';
import 'dav/directory_favorites.dart';
import 'dav/directory_favorites_bar.dart';
import 'organizer_state.dart';
import 'dav/empty_directory_dialog.dart';
import 'dav/webdav.dart';
import 'connections/webdav_manager.dart';
import 'scrape/scrape_dialog.dart';
import '../settings/settings_tab.dart';

/// Panel width below which toolbars collapse to icon buttons.
const _compactPanelWidth = 520.0;

/// Directories with more entries than this get a name filter.
const _filterThreshold = 8;

class OrganizerPage extends ConsumerStatefulWidget {
  const OrganizerPage({super.key});
  @override
  ConsumerState<OrganizerPage> createState() => _OrganizerPageState();
}

class _OrganizerPageState extends ConsumerState<OrganizerPage> {
  final filter = TextEditingController();
  final _fileScrollController = ScrollController();
  final _entryFocus = FocusNode(debugLabel: 'NAS entries');
  String? _selectedEntryPath;
  bool _renamingEntry = false;

  bool get _desktop => switch (defaultTargetPlatform) {
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => true,
    _ => false,
  };

  void _selectEntry(DavEntry entry) {
    setState(() => _selectedEntryPath = entry.path);
    _entryFocus.requestFocus();
  }

  final _directoryScrollOffsets = <String, double>{};
  bool _savingFavorite = false;
  bool _savingSort = false;

  Future<void> _setSort(DirectorySort order) async {
    if (_savingSort) return;
    setState(() => _savingSort = true);
    try {
      await ref
          .read(settingsProvider.notifier)
          .update((settings) => settings.copyWith(directorySort: order));
      if (!mounted) return;
      _directoryScrollOffsets.clear();
      if (_fileScrollController.hasClients) _fileScrollController.jumpTo(0);
    } catch (_) {
      if (mounted) {
        notifyUser(
          context,
          context.l10n.sortSaveFailed,
          type: NoticeType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _savingSort = false);
    }
  }

  @override
  void dispose() {
    filter.dispose();
    _entryFocus.dispose();
    _fileScrollController.dispose();
    super.dispose();
  }

  OrganizerController get _controller => ref.read(organizerProvider.notifier);

  void _openDirectory(String? path) {
    final directory = ref.read(organizerProvider).directory;
    if (directory.isNotEmpty && _fileScrollController.hasClients) {
      _directoryScrollOffsets[directory] = _fileScrollController.offset;
    }
    _controller.open(path);
  }

  String? _parentDirectory(OrganizerState state, String root) {
    if (state.directory.isEmpty || state.directory == root) return null;
    final parent = state.directory.replaceFirst(RegExp(r'[^/]+/$'), '');
    return parent.isNotEmpty && parent.startsWith(root) ? parent : null;
  }

  void _openParent(String root) {
    final state = ref.read(organizerProvider);
    if (state.busy || state.executing) return;
    final parent = _parentDirectory(state, root);
    if (parent != null) _openDirectory(parent);
  }

  Future<void> _toggleFavorite(
    NasScope scope,
    String directory, {
    required bool selected,
  }) async {
    if (_savingFavorite) return;
    setState(() => _savingFavorite = true);
    try {
      final repository = ref.read(directoryFavoritesRepositoryProvider);
      if (selected) {
        await repository.remove(scope, directory);
      } else {
        await repository.add(scope, directory);
      }
      if (mounted) ref.invalidate(directoryFavoritesProvider(scope));
    } catch (_) {
      if (mounted) {
        notifyUser(
          context,
          context.l10n.favoriteSaveFailed,
          type: NoticeType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _savingFavorite = false);
    }
  }

  Future<void> _renameEntry(DavEntry entry) async {
    final connection = ref.read(connectionSettingsProvider).asData?.value;
    final state = ref.read(organizerProvider);
    if (_renamingEntry || state.busy || state.executing) return;
    _renamingEntry = true;
    try {
      final target = await showFDialog<String>(
        context: context,
        useRootNavigator: true,
        useSafeArea: true,
        builder: (context, style, animation) =>
            _RenameEntryDialog(entry: entry, animation: animation),
      );
      if (target == null ||
          !mounted ||
          !identical(
            connection,
            ref.read(connectionSettingsProvider).asData?.value,
          )) {
        return;
      }
      await _controller.renameEntry(entry, target);
    } finally {
      _renamingEntry = false;
      if (mounted && _selectedEntryPath != null) _entryFocus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      connectionSettingsProvider.select(
        (value) => value.asData?.value.connectionId,
      ),
      (previous, next) {
        if (previous == next) return;
        filter.clear();
        _selectedEntryPath = null;
        _directoryScrollOffsets.clear();
      },
    );
    ref.listen(organizerProvider.select((s) => s.directory), (_, directory) {
      filter.clear();
      _selectedEntryPath = null;
      if (directory.isEmpty) _directoryScrollOffsets.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !_fileScrollController.hasClients ||
            ref.read(organizerProvider).directory != directory) {
          return;
        }
        final position = _fileScrollController.position;
        _fileScrollController.jumpTo(
          (_directoryScrollOffsets[directory] ?? 0).clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          ),
        );
      });
    });
    final state = ref.watch(organizerProvider);
    final settings = ref.watch(connectionSettingsProvider);
    final config = settings.asData?.value;
    if (config == null && settings.isLoading) {
      return const PageContent(children: [LoadingNotice()]);
    }
    if (config == null || config.webdavUrl.isEmpty) {
      return PageContent(
        children: [
          EmptyNotice(
            context.l10n.noConnectionConfigured,
            icon: FLucideIcons.hardDrive,
            child: FButton(
              mainAxisSize: MainAxisSize.min,
              prefix: const Icon(FLucideIcons.settings2),
              onPress: () => context.go(SettingsTab.webdav.location),
              child: Text(context.l10n.configureConnection),
            ),
          ),
        ],
      );
    }
    final locked = state.busy || state.executing;
    final base = Uri.parse(config.webdavUrl).path;
    final root = canonicalDavPath(base.endsWith('/') ? base : '$base/');

    final status = _status(context, state);
    final content = ColoredBox(
      key: const ValueKey('organizer-page-background'),
      color: context.theme.colors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: PageContent(
              fill: true,
              topPadding: 8,
              children: [
                if (status != null) ...[status, const SizedBox(height: 16)],
                Expanded(
                  child: _browser(
                    context,
                    state,
                    locked: locked,
                    root: root,
                    scope: nasScope(config),
                  ),
                ),
              ],
            ),
          ),
          _bottomActions(
            context,
            state,
            locked: locked,
            root: root,
            scope: nasScope(config),
          ),
        ],
      ),
    );
    final desktop = _desktop;
    return PopScope<Object?>(
      canPop: _parentDirectory(state, root) == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _openParent(root);
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: desktop
            ? (event) {
                if (event.kind == PointerDeviceKind.mouse &&
                    event.buttons & kBackMouseButton != 0) {
                  _openParent(root);
                }
              }
            : null,
        child: content,
      ),
    );
  }

  Widget _bottomActions(
    BuildContext context,
    OrganizerState state, {
    required bool locked,
    required String root,
    required NasScope scope,
  }) {
    final padding = PageContent.paddingOf(context);
    final selectionTextStyle = context.theme.typography.body.sm;
    return DecoratedBox(
      key: const ValueKey('organizer-bottom-actions'),
      decoration: BoxDecoration(
        color: context.theme.colors.background,
        border: Border(top: BorderSide(color: context.theme.colors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Align(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: PageContent.maxWidth),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: padding, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: state.selectedDirectories.isEmpty
                            ? const SizedBox.shrink()
                            : Text(
                                context.l10n.selectedDirectoryCount(
                                  state.selectedDirectories.length,
                                ),
                                style: selectionTextStyle,
                              ),
                      ),
                      if (state.selectedDirectories.isNotEmpty) ...[
                        FButton(
                          variant: .ghost,
                          size: .sm,
                          onPress: locked
                              ? null
                              : () => _controller.selectDirectories([]),
                          child: Text(
                            context.l10n.clearDirectorySelection,
                            style: selectionTextStyle,
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      FButton(
                        variant: .ghost,
                        size: .sm,
                        onPress:
                            locked || !state.entries.any((e) => e.directory)
                            ? null
                            : () => _controller.selectDirectories([
                                ...state.selectedDirectories,
                                for (final entry in state.entries)
                                  if (entry.directory &&
                                      (filter.text.isEmpty ||
                                          entry.name.toLowerCase().contains(
                                            filter.text.toLowerCase(),
                                          )))
                                    entry.path,
                              ]),
                        child: Text(
                          context.l10n.selectAllDirectories,
                          style: selectionTextStyle,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (state.directory.isNotEmpty) ...[
                        _directoryTools(
                          context,
                          state,
                          locked: locked,
                          root: root,
                          scope: scope,
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: FButton(
                          builder: responsiveButtonContent,
                          prefix: const Icon(FLucideIcons.arrowRight),
                          onPress:
                              locked ||
                                  (state.entries.isEmpty &&
                                      state.selectedDirectories.isEmpty)
                              ? null
                              : () => context.go('/assistant'),
                          child: Text(
                            state.selectedDirectories.isEmpty
                                ? context.l10n.organizeDirectory
                                : context.l10n.organizeSelectedDirectories(
                                    state.selectedDirectories.length,
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _directoryTools(
    BuildContext context,
    OrganizerState state, {
    required bool locked,
    required String root,
    required NasScope scope,
  }) {
    final parent = _parentDirectory(state, root);
    final paths = ref.watch(directoryFavoritesProvider(scope)).asData?.value;
    final selected =
        paths?.contains(favoriteDirectory(state.directory)) ?? false;
    Widget tool(
      IconData icon,
      String label,
      VoidCallback? onPress, {
      bool active = false,
    }) => FTooltip(
      tipBuilder: (_, _) => Text(label),
      child: FButton.icon(
        variant: active ? .primary : .outline,
        onPress: onPress,
        semanticsLabel: label,
        child: Icon(icon),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        tool(
          FLucideIcons.arrowUp,
          context.l10n.parentDirectory,
          locked || parent == null ? null : () => _openParent(root),
        ),
        const SizedBox(width: 8),
        tool(
          FLucideIcons.refreshCw,
          context.l10n.refreshDirectory,
          locked ? null : () => _openDirectory(state.directory),
        ),
        const SizedBox(width: 8),
        tool(
          FLucideIcons.star,
          selected
              ? context.l10n.unfavoriteDirectory
              : context.l10n.favoriteDirectory,
          locked || _savingFavorite || paths == null
              ? null
              : () =>
                    _toggleFavorite(scope, state.directory, selected: selected),
          active: selected,
        ),
        const SizedBox(width: 8),
        DirectoryFavoritesButton(
          scope: scope,
          directory: state.directory,
          locked: locked,
          onOpen: _openDirectory,
        ),
      ],
    );
  }

  Widget? _status(BuildContext context, OrganizerState state) {
    final theme = context.theme;
    if (state.busy && !state.executing) {
      return null;
    }
    if (state.executing || state.busy) {
      double? value;
      final parts = state.progress.split('/');
      if (state.executing && parts.length == 2) {
        final done = int.tryParse(parts[0].trim());
        final total = int.tryParse(parts[1].trim());
        if (done != null && total != null && total > 0) value = done / total;
      }
      final label = state.executing
          ? context.l10n.renaming
          : state.message.isEmpty
          ? context.l10n.processing
          : localizeRuntimeMessage(context.l10n, state.message);
      return Surface(
        padding: 16,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(label)),
                if (state.executing && state.progress.isNotEmpty)
                  Text(
                    localizeRuntimeMessage(context.l10n, state.progress),
                    style: theme.typography.body.sm.copyWith(
                      color: theme.colors.mutedForeground,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            value == null
                ? const FProgress()
                : FDeterminateProgress(value: value),
          ],
        ),
      );
    }
    if (state.message.isEmpty || !state.hasError) return null;
    return FAlert(
      variant: .destructive,
      icon: const Icon(FLucideIcons.circleAlert),
      title: Text(localizeRuntimeMessage(context.l10n, state.message)),
    );
  }

  Widget _browser(
    BuildContext context,
    OrganizerState state, {
    required bool locked,
    required String root,
    required NasScope scope,
  }) {
    final connected = state.directory.isNotEmpty;

    final query = filter.text.trim().toLowerCase();
    final order = ref.watch(
      settingsProvider.select((settings) => settings.directorySort),
    );
    final sorted = sortDirectoryEntries(state.entries, order);
    final visible = query.isEmpty
        ? sorted
        : sorted.where((e) => e.name.toLowerCase().contains(query)).toList();
    if (!visible.any((entry) => entry.path == _selectedEntryPath)) {
      _selectedEntryPath = null;
    }
    final planned = {
      for (final item in state.plan)
        if (item.enabled && item.source != item.target) item.source,
    };

    return Surface(
      key: const ValueKey('nas-browser'),
      padding: 0,
      child: LayoutBuilder(
        builder: (context, box) {
          final compact = box.maxWidth < _compactPanelWidth;
          final mobile = isMobileLayout(context);
          const connection = WebDavManager(compact: true);
          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (connected) ...[
                FPopoverMenu(
                  menuAnchor: Alignment.topRight,
                  childAnchor: Alignment.bottomRight,
                  menu: [
                    FItemGroup(
                      children: [
                        for (final (value, label) in [
                          (DirectorySort.nameAscending, context.l10n.sortName),
                          (
                            DirectorySort.modifiedDescending,
                            context.l10n.sortModified,
                          ),
                          (DirectorySort.sizeDescending, context.l10n.sortSize),
                        ])
                          FItem(
                            key: ValueKey('directory-sort-${value.name}'),
                            title: Text(label),
                            semanticsLabel: order.sameField(value)
                                ? '$label · ${order.ascending ? context.l10n.sortAscending : context.l10n.sortDescending}'
                                : label,
                            semanticsChecked: order.sameField(value),
                            suffix: order.sameField(value)
                                ? Icon(
                                    order.ascending
                                        ? FLucideIcons.arrowUp
                                        : FLucideIcons.arrowDown,
                                  )
                                : null,
                            onPress: locked || _savingSort
                                ? null
                                : () => _setSort(
                                    order.sameField(value)
                                        ? order.reversed
                                        : value,
                                  ),
                          ),
                      ],
                    ),
                  ],
                  builder: (_, controller, _) => FButton.icon(
                    key: const ValueKey('directory-sort'),
                    variant: .outline,
                    size: .sm,
                    semanticsLabel: context.l10n.sortDirectory,
                    onPress: locked || _savingSort ? null : controller.toggle,
                    child: const Icon(FLucideIcons.arrowUpDown),
                  ),
                ),
                const SizedBox(width: 8),
                if (mobile)
                  FPopoverMenu(
                    menuAnchor: Alignment.topRight,
                    childAnchor: Alignment.bottomRight,
                    menuBuilder: (_, controller, _) => [
                      FItemGroup(
                        children: [
                          ...scrapeMenuItems(context, controller, locked),
                          FItem(
                            key: const ValueKey('empty-directory-cleanup'),
                            prefix: const Icon(FLucideIcons.folderMinus),
                            title: Text(context.l10n.cleanEmptyDirectories),
                            onPress: locked
                                ? null
                                : () async {
                                    await controller.hide();
                                    if (context.mounted) {
                                      await showEmptyDirectoryDialog(context);
                                    }
                                  },
                          ),
                          FItem(
                            key: const ValueKey('nas-connection-toggle'),
                            prefix: const Icon(FLucideIcons.unplug),
                            title: Text(context.l10n.disconnect),
                            onPress: locked
                                ? null
                                : () async {
                                    await controller.hide();
                                    if (context.mounted) {
                                      _controller.disconnect();
                                    }
                                  },
                          ),
                        ],
                      ),
                    ],
                    builder: (_, controller, _) => FButton.icon(
                      key: const ValueKey('nas-browser-actions'),
                      variant: .outline,
                      size: .sm,
                      semanticsLabel: context.l10n.entryActions(
                        context.l10n.filesTab,
                      ),
                      onPress: locked ? null : controller.toggle,
                      child: const Icon(FLucideIcons.ellipsis),
                    ),
                  )
                else ...[
                  const ScrapeButton(),
                  const SizedBox(width: 8),
                  const EmptyDirectoryButton(),
                ],
              ],
              if (!mobile || !connected) ...[
                if (connected) const SizedBox(width: 8),
                if (box.maxWidth < 360 && connected)
                  FTooltip(
                    tipBuilder: (_, _) => Text(context.l10n.disconnect),
                    child: FButton.icon(
                      key: const ValueKey('nas-connection-toggle'),
                      variant: .outline,
                      size: .sm,
                      semanticsLabel: context.l10n.disconnect,
                      onPress: locked ? null : _controller.disconnect,
                      child: const Icon(FLucideIcons.unplug),
                    ),
                  )
                else
                  FButton(
                    key: const ValueKey('nas-connection-toggle'),
                    variant: connected ? .outline : .primary,
                    size: .sm,
                    mainAxisSize: MainAxisSize.min,
                    onPress: locked
                        ? null
                        : connected
                        ? _controller.disconnect
                        : () => _openDirectory(null),
                    prefix: Icon(
                      connected ? FLucideIcons.unplug : FLucideIcons.plugZap,
                    ),
                    child: Text(
                      connected
                          ? context.l10n.disconnect
                          : context.l10n.connectNas,
                    ),
                  ),
              ],
            ],
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                key: const ValueKey('nas-browser-toolbar'),
                padding: compact
                    ? const EdgeInsets.fromLTRB(16, 10, 16, 8)
                    : const EdgeInsets.fromLTRB(20, 18, 16, 12),
                child: !mobile && connected && box.maxWidth < 500
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Expanded(child: connection),
                              const SizedBox(width: 8),
                              actions.children.first,
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: actions.children.skip(2).toList(),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(child: connection),
                          SizedBox(width: compact ? 8 : 16),
                          actions,
                        ],
                      ),
              ),
              if (connected) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: DirectoryBreadcrumb(
                    key: const ValueKey('directory-breadcrumb'),
                    directory: state.directory,
                    root: root,
                    locked: locked,
                    onOpen: (path) => _openDirectory(path),
                    currentKey: const ValueKey('directory-current-crumb'),
                  ),
                ),
                const SizedBox(height: 6),
                if (state.entries.length > _filterThreshold)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                    child: FTextField(
                      control: .managed(
                        controller: filter,
                        onChange: (_) => setState(() {}),
                      ),
                      hint: context.l10n.filterByName,
                    ),
                  ),
              ],
              SizedBox(
                height: 2,
                child: state.busy
                    ? const FProgress()
                    : const Center(child: _Divider()),
              ),
              Expanded(
                child: Focus(
                  focusNode: _entryFocus,
                  onKeyEvent: (node, event) {
                    if (!_desktop ||
                        !node.hasPrimaryFocus ||
                        locked ||
                        _renamingEntry ||
                        event is! KeyDownEvent ||
                        event.logicalKey != LogicalKeyboardKey.f2) {
                      return KeyEventResult.ignored;
                    }
                    for (final entry in visible) {
                      if (entry.path == _selectedEntryPath) {
                        _renameEntry(entry);
                        return KeyEventResult.handled;
                      }
                    }
                    return KeyEventResult.ignored;
                  },
                  child: ClipRect(
                    child: !connected || visible.isEmpty
                        ? Center(
                            key: const ValueKey('nas-empty-state'),
                            child: EmptyState(
                              !connected
                                  ? context.l10n.browseNasHint
                                  : state.entries.isEmpty
                                  ? context.l10n.directoryEmpty
                                  : context.l10n.noNameMatches,
                              icon: !connected
                                  ? FLucideIcons.hardDrive
                                  : state.entries.isEmpty
                                  ? FLucideIcons.folderOpen
                                  : FLucideIcons.search,
                              child: connected && state.entries.isNotEmpty
                                  ? FButton(
                                      variant: .outline,
                                      mainAxisSize: MainAxisSize.min,
                                      onPress: () {
                                        filter.clear();
                                        setState(() {});
                                      },
                                      child: Text(context.l10n.clearFilters),
                                    )
                                  : null,
                            ),
                          )
                        : ListView.builder(
                            key: const ValueKey('nas-file-list'),
                            controller: _fileScrollController,
                            primary: false,
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            itemCount: visible.length,
                            itemBuilder: (context, index) {
                              final entry = visible[index];
                              return _EntryRow(
                                key: ValueKey(entry.path),
                                entry: entry,
                                locked: locked,
                                compact: compact,
                                desktop: _desktop,
                                selected:
                                    _desktop &&
                                    entry.path == _selectedEntryPath,
                                onSelect: () => _selectEntry(entry),
                                planned: planned.contains(entry.path),
                                onOpen: () => _openDirectory(entry.path),
                                onRename: () => _renameEntry(entry),
                                checked: state.selectedDirectories.contains(
                                  entry.path,
                                ),
                                onToggle: () =>
                                    _controller.toggleDirectory(entry.path),
                              );
                            },
                          ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RenameEntryDialog extends StatefulWidget {
  const _RenameEntryDialog({required this.entry, required this.animation});

  final DavEntry entry;
  final Animation<double> animation;

  @override
  State<_RenameEntryDialog> createState() => _RenameEntryDialogState();
}

class _RenameEntryDialogState extends State<_RenameEntryDialog> {
  late final TextEditingController name;
  late final TextEditingController extension;
  String? issue;

  @override
  void initState() {
    super.initState();
    final original = widget.entry.name;
    final dot = original.lastIndexOf('.');
    final split =
        !widget.entry.directory && dot > 0 && dot < original.length - 1;
    name = TextEditingController(
      text: split ? original.substring(0, dot) : original,
    );
    extension = TextEditingController(
      text: split ? original.substring(dot + 1) : '',
    );
  }

  String get targetName => widget.entry.directory || extension.text.isEmpty
      ? name.text
      : '${name.text}.${extension.text}';

  void _validate() => setState(() {
    issue = name.text.trim().isEmpty
        ? fileNameError(name.text)
        : fileNameError(targetName);
  });

  @override
  void dispose() {
    name.dispose();
    extension.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FDialog(
    animation: widget.animation,
    builder: (context, style) => SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.renameEntry,
            style: context.theme.typography.body.lg,
          ),
          const SizedBox(height: 16),
          FTextField(
            key: const ValueKey('rename-entry-name'),
            label: Text(context.l10n.newFileName),
            control: .managed(controller: name, onChange: (_) => _validate()),
          ),
          if (!widget.entry.directory) ...[
            const SizedBox(height: 12),
            FTextField(
              key: const ValueKey('rename-entry-extension'),
              label: Text(context.l10n.fileExtension),
              control: .managed(
                controller: extension,
                onChange: (_) => _validate(),
              ),
            ),
          ],
          if (issue != null) ...[
            const SizedBox(height: 8),
            Text(
              issue!,
              style: TextStyle(color: context.theme.colors.destructive),
            ),
          ],
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 12,
            runSpacing: 10,
            children: [
              FButton(
                variant: .outline,
                mainAxisSize: MainAxisSize.min,
                onPress: () => Navigator.of(context).pop(),
                child: Text(context.l10n.cancel),
              ),
              FButton(
                mainAxisSize: MainAxisSize.min,
                onPress: issue != null || targetName == widget.entry.name
                    ? null
                    : () => Navigator.of(context).pop(targetName),
                child: Text(context.l10n.renameEntry),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.zero,
    child: SizedBox(
      height: 1,
      child: ColoredBox(color: context.theme.colors.border),
    ),
  );
}

const _videoExtensions = {
  'mkv', 'mp4', 'avi', 'mov', 'wmv', 'flv', 'ts', 'm2ts', 'webm', 'rmvb', //
  'iso', 'm4v', 'mpg', 'mpeg',
};
const _subtitleExtensions = {'srt', 'ass', 'ssa', 'vtt', 'sub', 'sup', 'idx'};
const _textExtensions = {'nfo', 'txt', 'md', 'json', 'xml'};

IconData _entryIcon(DavEntry entry) {
  if (entry.directory) return FLucideIcons.folder;
  final name = entry.name.toLowerCase();
  final extension = name.contains('.') ? name.split('.').last : '';
  if (_videoExtensions.contains(extension)) return FLucideIcons.fileVideoCamera;
  if (_subtitleExtensions.contains(extension)) return FLucideIcons.captions;
  if (_textExtensions.contains(extension)) return FLucideIcons.fileText;
  return FLucideIcons.file;
}

String _formatSize(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return unit == 0
      ? '$bytes B'
      : '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[unit]}';
}

String? _formatModified(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    final date = HttpDate.parse(raw).toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)}';
  } catch (_) {
    return raw;
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.locked,
    required this.compact,
    required this.planned,
    required this.desktop,
    required this.selected,
    required this.onSelect,
    required this.onOpen,
    required this.onRename,
    required this.checked,
    required this.onToggle,
    super.key,
  });
  final DavEntry entry;
  final bool locked, compact, planned, desktop, selected;
  final VoidCallback onSelect;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final bool checked;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final details = [
      if (entry.directory) context.l10n.folder,
      if (!entry.directory && entry.size != null) _formatSize(entry.size!),
      if (!compact || entry.directory) ?_formatModified(entry.modified),
    ].join(' · ');
    return Semantics(
      selected: desktop ? selected : null,
      child: FTappable(
        onPress: locked
            ? null
            : desktop
            ? onSelect
            : entry.directory
            ? onOpen
            : null,
        onDoubleTap: desktop && entry.directory && !locked ? onOpen : null,
        semanticsLabel: entry.directory
            ? context.l10n.openEntry(entry.name)
            : entry.name,
        builder: (context, variants, child) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color:
                selected ||
                    (desktop || entry.directory) &&
                        !locked &&
                        (variants.contains(FTappableVariant.hovered) ||
                            variants.contains(FTappableVariant.pressed))
                ? theme.colors.secondary
                : null,
            borderRadius: theme.style.borderRadius.md,
          ),
          child: child,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: [
              if (entry.directory) ...[
                FCheckbox(
                  value: checked,
                  enabled: !locked,
                  onChange: (_) => onToggle(),
                ),
                const SizedBox(width: 12),
              ],
              Icon(
                _entryIcon(entry),
                size: 20,
                color: entry.directory
                    ? theme.colors.primary
                    : theme.colors.mutedForeground,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.typography.body.sm,
                    ),
                    if (details.isNotEmpty)
                      Text(
                        details,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.typography.body.xs.copyWith(
                          color: theme.colors.mutedForeground,
                        ),
                      ),
                  ],
                ),
              ),
              if (planned) ...[
                const SizedBox(width: 8),
                FBadge(
                  variant: .secondary,
                  child: Text(
                    compact
                        ? context.l10n.pendingRenameShort
                        : context.l10n.pendingRename,
                  ),
                ),
              ],
              const SizedBox(width: 4),
              FPopoverMenu(
                menuAnchor: Alignment.topRight,
                childAnchor: Alignment.bottomRight,
                menuBuilder: (context, controller, _) => [
                  FItemGroup(
                    children: [
                      FItem(
                        prefix: const Icon(FLucideIcons.pencil, size: 16),
                        title: Text(context.l10n.renameEntry),
                        onPress: () {
                          controller.hide();
                          onRename();
                        },
                      ),
                    ],
                  ),
                ],
                builder: (context, controller, _) => FButton.icon(
                  variant: .ghost,
                  size: .sm,
                  semanticsLabel: context.l10n.entryActions(entry.name),
                  onPress: locked ? null : controller.toggle,
                  child: const Icon(FLucideIcons.ellipsis, size: 16),
                ),
              ),
              if (entry.directory)
                Icon(
                  FLucideIcons.chevronRight,
                  size: 16,
                  color: theme.colors.mutedForeground,
                )
              else
                const SizedBox(width: 16),
            ],
          ),
        ),
      ),
    );
  }
}
