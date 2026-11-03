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
import '../../shared/organizer_stepper.dart';
import 'ai/ai_usage.dart';
import 'connections/connection_settings.dart';
import 'dav/dav_paths.dart';
import 'dav/directory_sort.dart';
import 'dav/directory_favorites.dart';
import 'dav/directory_favorites_bar.dart';
import 'organizer_state.dart';
import 'rename_plan.dart';
import 'dav/webdav.dart';

/// Panel width below which toolbars collapse to icon buttons.
const _compactPanelWidth = 520.0;

/// Directories with more entries than this get a name filter.
const _filterThreshold = 8;

enum OrganizerStep { browse, assistant, preview }

class OrganizerPage extends ConsumerStatefulWidget {
  const OrganizerPage({this.step = OrganizerStep.browse, super.key});

  final OrganizerStep step;
  @override
  ConsumerState<OrganizerPage> createState() => _OrganizerPageState();
}

class _OrganizerPageState extends ConsumerState<OrganizerPage> {
  final instruction = TextEditingController();
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
    instruction.dispose();
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

  Future<bool> _confirm(
    String title, {
    String? detail,
    String? action,
    bool destructive = false,
  }) async =>
      await showFDialog<bool>(
        context: context,
        builder: (context, style, animation) => FDialog(
          animation: animation,
          builder: (context, style) => EscapeDismiss(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: context.theme.typography.body.lg),
                  if (detail != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      detail,
                      style: context.theme.typography.body.sm.copyWith(
                        color: context.theme.colors.mutedForeground,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  _DialogActions(
                    action: action ?? context.l10n.confirmAction,
                    destructive: destructive,
                    onConfirm: () => Navigator.of(context).pop(true),
                  ),
                ],
              ),
            ),
          ),
        ),
      ) ??
      false;

  Future<void> _favorites(NasScope scope, String directory) async {
    final path = await showDirectoryFavoritesDialog(
      context,
      scope: scope,
      directory: directory,
    );
    if (path != null && mounted) _openDirectory(path);
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

  Future<void> _propose() async {
    if (await _confirm(
          context.l10n.analyzeDirectory,
          detail: context.l10n.analyzeDirectoryDetail,
          action: context.l10n.startAnalysis,
        ) &&
        mounted) {
      await _controller.propose(instruction: instruction.text.trim());
      if (mounted && ref.read(organizerProvider).plan.isNotEmpty) {
        context.go('/organize/assistant/preview');
      }
    }
  }

  Future<void> _execute() async {
    if (await _confirm(
          context.l10n.executeRenames,
          detail: context.l10n.executeRenamesDetail,
          action: context.l10n.startExecution,
        ) &&
        mounted) {
      await _controller.execute();
    }
  }

  Future<void> _renameEntry(DavEntry entry) async {
    final state = ref.read(organizerProvider);
    if (_renamingEntry || state.busy || state.executing) return;
    _renamingEntry = true;
    try {
      final target = await showFDialog<String>(
        context: context,
        builder: (context, style, animation) =>
            _RenameEntryDialog(entry: entry, animation: animation),
      );
      if (target == null || !mounted) return;
      await _controller.renameEntry(entry, target);
    } finally {
      _renamingEntry = false;
      if (mounted && _selectedEntryPath != null) _entryFocus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
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
            child: FButton(
              mainAxisSize: MainAxisSize.min,
              prefix: const Icon(FLucideIcons.settings2),
              onPress: () => context.go('/connections'),
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
    const gap = SizedBox(height: 16);
    final content = ColoredBox(
      key: const ValueKey('organizer-page-background'),
      color: context.theme.colors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.center,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: PageContent.maxWidth),
              child: SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    PageContent.paddingOf(context),
                    12,
                    PageContent.paddingOf(context),
                    4,
                  ),
                  child: _navigation(context, locked: locked),
                ),
              ),
            ),
          ),
          Expanded(
            child: PageContent(
              fill: widget.step == OrganizerStep.browse,
              topPadding: 8,
              children: [
                if (status != null) ...[status, gap],
                if (widget.step != OrganizerStep.browse &&
                    state.aiUsage != null) ...[
                  AiUsagePanel(usage: state.aiUsage!, pricing: state.pricing),
                  gap,
                ],
                switch (widget.step) {
                  OrganizerStep.browse => Expanded(
                    child: _browser(
                      context,
                      state,
                      locked: locked,
                      root: root,
                      scope: nasScope(config),
                    ),
                  ),
                  OrganizerStep.assistant => _assistant(
                    context,
                    state,
                    locked: locked,
                  ),
                  OrganizerStep.preview => _plan(
                    context,
                    state,
                    locked: locked,
                  ),
                },
              ],
            ),
          ),
          if (widget.step == OrganizerStep.browse ||
              widget.step == OrganizerStep.preview && state.plan.isNotEmpty)
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
    if (widget.step != OrganizerStep.browse) return content;

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
    final preview = widget.step == OrganizerStep.preview;
    final canExecute =
        !locked &&
        validatePlan(
              state.plan,
              state.analysisEntries.isEmpty
                  ? state.entries
                  : state.analysisEntries,
            ) ==
            null &&
        state.plan.any((item) => item.enabled && item.source != item.target);
    final padding = PageContent.paddingOf(context);
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
                  if (preview) ...[
                    Text(
                      context.l10n.executionSafety,
                      style: context.theme.typography.body.sm.copyWith(
                        color: context.theme.colors.mutedForeground,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (preview)
                    FButton(
                      builder: responsiveButtonContent,
                      prefix: const Icon(FLucideIcons.play),
                      onPress: canExecute ? _execute : null,
                      child: Text(context.l10n.confirmAndExecute),
                    )
                  else
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
                            onPress: locked || state.entries.isEmpty
                                ? null
                                : () => context.go('/organize/assistant'),
                            child: Text(context.l10n.organizeDirectory),
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
        tool(
          FLucideIcons.list,
          context.l10n.favorites,
          locked ? null : () => _favorites(scope, state.directory),
        ),
      ],
    );
  }

  Widget _navigation(BuildContext context, {required bool locked}) =>
      OrganizerStepper(
        key: const ValueKey('organizer-stepper'),
        currentStep: widget.step.index,
        locked: locked,
        onStepSelected: (index) => context.go(
          const [
            '/organize',
            '/organize/assistant',
            '/organize/assistant/preview',
          ][index],
        ),
      );

  Widget? _status(BuildContext context, OrganizerState state) {
    final theme = context.theme;
    if (widget.step == OrganizerStep.browse && state.busy && !state.executing) {
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
    final theme = context.theme;
    final connected = state.directory.isNotEmpty;

    final crumbs = <(String, String)>[];
    if (state.directory.startsWith(root)) {
      crumbs.add((context.l10n.rootDirectory, root));
      var path = root;
      for (final segment
          in state.directory
              .substring(root.length)
              .split('/')
              .where((s) => s.isNotEmpty)) {
        path = '$path$segment/';
        crumbs.add((Uri.decodeComponent(segment), path));
      }
    } else if (connected) {
      crumbs.add((displayDavPath(state.directory), state.directory));
    }

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
    final folders = state.entries.where((e) => e.directory).length;
    final files = state.entries.length - folders;

    return Surface(
      key: const ValueKey('nas-browser'),
      padding: 0,
      child: LayoutBuilder(
        builder: (context, box) {
          final compact = box.maxWidth < _compactPanelWidth;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 16, 12),
                child: Row(
                  children: [
                    Icon(
                      FLucideIcons.server,
                      size: 18,
                      color: theme.colors.mutedForeground,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.nasDirectory,
                            style: theme.typography.body.lg,
                          ),
                          if (connected)
                            Text(
                              context.l10n.directoryCounts(folders, files),
                              style: theme.typography.body.xs.copyWith(
                                color: theme.colors.mutedForeground,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (connected) ...[
                      FPopoverMenu(
                        menuAnchor: Alignment.topRight,
                        childAnchor: Alignment.bottomRight,
                        menu: [
                          FItemGroup(
                            children: [
                              for (final (value, label) in [
                                (
                                  DirectorySort.nameAscending,
                                  context.l10n.sortName,
                                ),
                                (
                                  DirectorySort.modifiedDescending,
                                  context.l10n.sortModified,
                                ),
                                (
                                  DirectorySort.sizeDescending,
                                  context.l10n.sortSize,
                                ),
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
                          onPress: locked || _savingSort
                              ? null
                              : controller.toggle,
                          child: const Icon(FLucideIcons.arrowUpDown),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    FButton(
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
                ),
              ),
              if (connected) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: FBreadcrumb(
                    key: const ValueKey('directory-breadcrumb'),
                    children: [
                      if (crumbs.length > 1)
                        FBreadcrumbItem(
                          onPress: locked ? null : () => _openDirectory(root),
                          child: Text(crumbs.first.$1),
                        ),
                      if (crumbs.length > 2)
                        FBreadcrumbItem.collapsed(
                          key: const ValueKey('directory-ancestors'),
                          semanticsLabel: context.l10n.parentDirectories,
                          maxHeight: 320,
                          menu: [
                            FItemGroup(
                              children: [
                                for (final (label, path)
                                    in crumbs.skip(1).take(crumbs.length - 2))
                                  FItem(
                                    key: ValueKey('directory-ancestor-$path'),
                                    title: Text(
                                      label,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    onPress: locked
                                        ? null
                                        : () => _openDirectory(path),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      if (crumbs.isNotEmpty)
                        Expanded(
                          child: FTooltip(
                            tipBuilder: (_, _) =>
                                Text(displayDavPath(state.directory)),
                            child: FBreadcrumbItem(
                              current: true,
                              child: Text(
                                crumbs.last.$1,
                                key: const ValueKey('directory-current-crumb'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
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
                            child: _Placeholder(
                              icon: !connected
                                  ? FLucideIcons.hardDrive
                                  : state.entries.isEmpty
                                  ? FLucideIcons.folderOpen
                                  : FLucideIcons.search,
                              message: !connected
                                  ? context.l10n.browseNasHint
                                  : state.entries.isEmpty
                                  ? context.l10n.directoryEmpty
                                  : context.l10n.noNameMatches(
                                      filter.text.trim(),
                                    ),
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

  Widget _assistant(
    BuildContext context,
    OrganizerState state, {
    required bool locked,
  }) {
    final theme = context.theme;
    final hasFiles = state.entries.isNotEmpty;
    final canPropose = !locked && state.directory.isNotEmpty && hasFiles;
    final hint = state.directory.isEmpty
        ? context.l10n.openSeriesDirectory
        : !hasFiles
        ? context.l10n.openNonemptyDirectory
        : null;
    return Surface(
      padding: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                FLucideIcons.sparkles,
                size: 18,
                color: theme.colors.mutedForeground,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.l10n.aiSuggestions,
                  style: theme.typography.body.lg,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            displayDavPath(state.directory),
            style: theme.typography.body.sm,
          ),
          const SizedBox(height: 16),
          FTextField.multiline(
            key: const ValueKey('organizing-requirements'),
            control: .managed(controller: instruction),
            label: Text(context.l10n.optionalRequirements),
            hint: context.l10n.requirementsHint,
            enabled: !locked,
            minLines: 3,
            maxLines: 6,
            textInputAction: TextInputAction.newline,
          ),
          const SizedBox(height: 12),
          FButton(
            builder: responsiveButtonContent,
            prefix: Icon(
              state.analyzing ? FLucideIcons.square : FLucideIcons.sparkles,
            ),
            onPress: state.analyzing
                ? _controller.cancelSuggestions
                : canPropose
                ? _propose
                : null,
            child: Text(
              state.analyzing
                  ? context.l10n.stopSuggestions
                  : context.l10n.generateSuggestions,
            ),
          ),
          if (state.plan.isNotEmpty) ...[
            const SizedBox(height: 12),
            FButton(
              variant: .outline,
              onPress: locked
                  ? null
                  : () => context.go('/organize/assistant/preview'),
              child: Text(context.l10n.viewRenamePreview),
            ),
          ],
          if (hint != null) ...[
            const SizedBox(height: 10),
            Text(
              hint,
              style: theme.typography.body.xs.copyWith(
                color: theme.colors.mutedForeground,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _plan(
    BuildContext context,
    OrganizerState state, {
    required bool locked,
  }) {
    final theme = context.theme;
    final muted = theme.typography.body.sm.copyWith(
      color: theme.colors.mutedForeground,
    );
    if (state.plan.isEmpty) {
      return Surface(
        padding: 20,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  FLucideIcons.listChecks,
                  size: 18,
                  color: theme.colors.mutedForeground,
                ),
                const SizedBox(width: 10),
                Text(
                  context.l10n.renamePreview,
                  style: theme.typography.body.lg,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(context.l10n.noPendingChanges, style: muted),
            const SizedBox(height: 12),
            if (state.message.startsWith('已完成 ')) ...[
              FButton(
                onPress: locked ? null : () => context.go('/organize'),
                child: Text(context.l10n.backToNasDirectory),
              ),
              const SizedBox(height: 12),
            ],
            FButton(
              variant: .outline,
              onPress: locked ? null : () => context.go('/organize/assistant'),
              child: Text(context.l10n.backToRequirements),
            ),
          ],
        ),
      );
    }
    final error = validatePlan(
      state.plan,
      state.analysisEntries.isEmpty ? state.entries : state.analysisEntries,
    );
    final selected = state.plan.where((e) => e.enabled).length;
    final changes = state.plan
        .where((p) => p.enabled && p.source != p.target)
        .length;
    final allSelected = selected == state.plan.length;
    return Surface(
      padding: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 16, 14),
            child: Row(
              children: [
                Icon(
                  FLucideIcons.listChecks,
                  size: 18,
                  color: theme.colors.mutedForeground,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.renamePreview,
                        style: theme.typography.body.lg,
                      ),
                      Text(
                        context.l10n.selectedChanges(
                          selected,
                          state.plan.length,
                          changes,
                        ),
                        style: theme.typography.body.xs.copyWith(
                          color: theme.colors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FButton(
                  variant: .ghost,
                  size: .sm,
                  mainAxisSize: MainAxisSize.min,
                  onPress: locked
                      ? null
                      : () => _controller.setAllEnabled(!allSelected),
                  child: Text(
                    allSelected
                        ? context.l10n.deselectAll
                        : context.l10n.selectAll,
                  ),
                ),
              ],
            ),
          ),
          const _Divider(),
          for (final (index, item) in state.plan.indexed) ...[
            if (index > 0) const _Divider(indent: 16),
            _RenameRow(
              key: ValueKey(item.source),
              item: item,
              entries: state.analysisEntries.isEmpty
                  ? state.entries
                  : state.analysisEntries,
              disabled: locked,
              onName: (name) => _controller.edit(index, name: name),
              onEnabled: (enabled) => _controller.edit(index, enabled: enabled),
            ),
          ],
          if (error != null) ...[
            const _Divider(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FAlert(
                variant: .destructive,
                icon: const Icon(FLucideIcons.circleAlert),
                title: Text(context.l10n.cannotExecute),
                subtitle: Text(localizeRuntimeMessage(context.l10n, error)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class AiUsagePanel extends StatelessWidget {
  const AiUsagePanel({required this.usage, this.pricing, super.key});

  final AiUsage usage;
  final ModelPricing? pricing;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final available = usage.responses > 0 && !usage.missingUsage;
    final tps = usage.tokensPerSecond;
    final cost = pricing?.estimate(usage);
    final metrics = [
      (context.l10n.inputTokens, available ? '${usage.inputTokens}' : '—'),
      (context.l10n.outputTokens, available ? '${usage.outputTokens}' : '—'),
      (context.l10n.averageTps, tps?.toStringAsFixed(1) ?? '—'),
    ];
    return Surface(
      padding: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.l10n.analysisUsage, style: theme.typography.body.lg),
          const SizedBox(height: 16),
          Wrap(
            spacing: 32,
            runSpacing: 16,
            children: [
              for (final (label, value) in metrics)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: theme.typography.body.xs.copyWith(
                        color: theme.colors.mutedForeground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(value, style: theme.typography.body.lg),
                  ],
                ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.l10n.estimatedCost,
                    style: theme.typography.body.xs.copyWith(
                      color: theme.colors.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (cost == null)
                    Text('—', style: theme.typography.body.lg)
                  else
                    TweenAnimationBuilder<double>(
                      tween: Tween(end: cost),
                      duration: const Duration(milliseconds: 450),
                      builder: (context, value, _) => Text(
                        '\$${value.toStringAsFixed(6)}',
                        style: theme.typography.body.lg,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ],
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
  late final name = TextEditingController(text: widget.entry.name);
  String? issue;

  @override
  void dispose() {
    name.dispose();
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
            control: .managed(
              controller: name,
              onChange: (_) => setState(() => issue = fileNameError(name.text)),
            ),
          ),
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
                onPress: issue != null || name.text == widget.entry.name
                    ? null
                    : () => Navigator.of(context).pop(name.text),
                child: Text(context.l10n.renameEntry),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _DialogActions extends StatelessWidget {
  const _DialogActions({
    required this.action,
    required this.onConfirm,
    this.destructive = false,
  });
  final String action;
  final VoidCallback onConfirm;
  final bool destructive;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 10,
    alignment: WrapAlignment.end,
    children: [
      FButton(
        variant: .outline,
        mainAxisSize: MainAxisSize.min,
        onPress: () => Navigator.of(context).pop(),
        child: Text(context.l10n.cancel),
      ),
      FButton(
        variant: destructive ? .destructive : .primary,
        mainAxisSize: MainAxisSize.min,
        onPress: onConfirm,
        child: Text(action),
      ),
    ],
  );
}

class _Divider extends StatelessWidget {
  const _Divider({this.indent = 0});
  final double indent;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(horizontal: indent),
    child: SizedBox(
      height: 1,
      child: ColoredBox(color: context.theme.colors.border),
    ),
  );
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.icon, required this.message});
  final IconData icon;
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 28, color: context.theme.colors.mutedForeground),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: context.theme.typography.body.sm.copyWith(
            color: context.theme.colors.mutedForeground,
          ),
        ),
      ],
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
    super.key,
  });
  final DavEntry entry;
  final bool locked, compact, planned, desktop, selected;
  final VoidCallback onSelect;
  final VoidCallback onOpen;
  final VoidCallback onRename;

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

class _RenameRow extends StatefulWidget {
  const _RenameRow({
    required this.item,
    required this.entries,
    required this.disabled,
    required this.onName,
    required this.onEnabled,
    super.key,
  });
  final RenameItem item;
  final List<DavEntry> entries;
  final bool disabled;
  final ValueChanged<String> onName;
  final ValueChanged<bool> onEnabled;
  @override
  State<_RenameRow> createState() => _RenameRowState();
}

class _RenameRowState extends State<_RenameRow> {
  late final text = TextEditingController(text: widget.item.targetName);
  @override
  void didUpdateWidget(covariant _RenameRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (text.text != widget.item.targetName) text.text = widget.item.targetName;
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final item = widget.item;
    final original = item.targetDirectory == null
        ? Uri.decodeComponent(item.source.split('/').last)
        : displayDavPath(item.source);
    final unchanged = item.source == item.target;
    final issue = item.enabled ? validatePlan([item], widget.entries) : null;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: item.enabled ? 1 : .55,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: FCheckbox(
                value: item.enabled,
                enabled: !widget.disabled,
                onChange: widget.onEnabled,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          original,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.typography.body.sm.copyWith(
                            color: theme.colors.mutedForeground,
                          ),
                        ),
                      ),
                      if (unchanged) ...[
                        const SizedBox(width: 8),
                        FBadge(
                          variant: .outline,
                          child: Text(context.l10n.unchanged),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  FTextField(
                    control: .managed(
                      controller: text,
                      onChange: (value) => widget.onName(value.text),
                    ),
                    enabled: !widget.disabled,
                    hint: context.l10n.newFileName,
                  ),
                  if (item.targetDirectory != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '→ ${displayDavPath(item.target)}',
                      style: theme.typography.body.xs.copyWith(
                        color: theme.colors.mutedForeground,
                      ),
                    ),
                  ],
                  if (issue != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      localizeRuntimeMessage(context.l10n, issue),
                      style: theme.typography.body.xs.copyWith(
                        color: theme.colors.destructive,
                      ),
                    ),
                  ],
                  if (item.reason.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      localizeRuntimeMessage(context.l10n, item.reason),
                      style: theme.typography.body.xs.copyWith(
                        color: theme.colors.mutedForeground,
                      ),
                    ),
                  ],
                  if (item.tmdbUrl case final url?) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FButton(
                        key: ValueKey('tmdb-link-${item.source}'),
                        variant: .ghost,
                        size: .sm,
                        mainAxisSize: MainAxisSize.min,
                        prefix: const Icon(FLucideIcons.externalLink),
                        onPress: () =>
                            openDocumentation(context, url.toString()),
                        child: Text(context.l10n.viewOnTmdb),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
