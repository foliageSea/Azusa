import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets.dart';
import 'ai/ai_usage.dart';
import 'connections/connection_settings.dart';
import 'dav/dav_paths.dart';
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
  bool _savingFavorite = false;

  @override
  void dispose() {
    instruction.dispose();
    filter.dispose();
    super.dispose();
  }

  OrganizerController get _controller => ref.read(organizerProvider.notifier);

  String? _parentDirectory(OrganizerState state, String root) {
    if (state.directory.isEmpty || state.directory == root) return null;
    final parent = state.directory.replaceFirst(RegExp(r'[^/]+/$'), '');
    return parent.isNotEmpty && parent.startsWith(root) ? parent : null;
  }

  void _openParent(String root) {
    final state = ref.read(organizerProvider);
    if (state.busy || state.executing) return;
    final parent = _parentDirectory(state, root);
    if (parent != null) _controller.open(parent);
  }

  Future<bool> _confirm(
    String title, {
    String? detail,
    String action = '确认',
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
                    action: action,
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
    if (path != null && mounted) await _controller.open(path);
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
        notifyUser(context, '保存收藏失败，请重试', type: NoticeType.error);
      }
    } finally {
      if (mounted) setState(() => _savingFavorite = false);
    }
  }

  Future<void> _propose() async {
    if (await _confirm(
          '将此目录发送给 AI 分析？',
          detail: '所选目录路径和文件名将发送至你配置的 AI 服务，文件内容不会上传。',
          action: '开始分析',
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
          '执行已选择的重命名？',
          detail: '将按预览逐项修改 NAS 文件名，遇到失败立即停止，不覆盖已有文件。',
          action: '开始执行',
        ) &&
        mounted) {
      await _controller.execute();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      organizerProvider.select((s) => s.directory),
      (_, _) => filter.clear(),
    );
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
            '尚未配置 NAS 连接。请先填写 WebDAV 地址、AI 服务与 TMDB 凭据。',
            child: FButton(
              mainAxisSize: MainAxisSize.min,
              prefix: const Icon(FLucideIcons.settings2),
              onPress: () => context.go('/connections'),
              child: const Text('配置连接'),
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
    final content = Column(
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
                OrganizerStep.preview => _plan(context, state, locked: locked),
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
    );
    if (widget.step != OrganizerStep.browse) return content;

    final desktop = switch (defaultTargetPlatform) {
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => true,
      _ => false,
    };
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
        validatePlan(state.plan, state.entries) == null &&
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
                      '逐项修改，遇到失败立即停止，不覆盖已有文件。',
                      style: context.theme.typography.body.sm.copyWith(
                        color: context.theme.colors.mutedForeground,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (preview)
                    FButton(
                      prefix: const Icon(FLucideIcons.play),
                      onPress: canExecute ? _execute : null,
                      child: const Text('确认并执行'),
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
                            prefix: const Icon(FLucideIcons.arrowRight),
                            onPress:
                                locked ||
                                    !state.entries.any((e) => !e.directory)
                                ? null
                                : () => context.go('/organize/assistant'),
                            child: const Text('整理此目录'),
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
          '返回上级',
          locked || parent == null ? null : () => _openParent(root),
        ),
        const SizedBox(width: 8),
        tool(
          FLucideIcons.refreshCw,
          '刷新目录',
          locked ? null : () => _controller.open(state.directory),
        ),
        const SizedBox(width: 8),
        tool(
          FLucideIcons.star,
          selected ? '取消收藏当前目录' : '收藏当前目录',
          locked || _savingFavorite || paths == null
              ? null
              : () =>
                    _toggleFavorite(scope, state.directory, selected: selected),
          active: selected,
        ),
        const SizedBox(width: 8),
        tool(
          FLucideIcons.list,
          '收藏列表',
          locked ? null : () => _favorites(scope, state.directory),
        ),
      ],
    );
  }

  Widget _navigation(BuildContext context, {required bool locked}) => Wrap(
    spacing: 12,
    runSpacing: 12,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      FBreadcrumb(
        children: [
          FBreadcrumbItem(
            current: widget.step == OrganizerStep.browse,
            onPress: locked || widget.step == OrganizerStep.browse
                ? null
                : () => context.go('/organize'),
            child: const Text('NAS 目录'),
          ),
          if (widget.step != OrganizerStep.browse)
            FBreadcrumbItem(
              current: widget.step == OrganizerStep.assistant,
              onPress: locked || widget.step == OrganizerStep.assistant
                  ? null
                  : () => context.go('/organize/assistant'),
              child: const Text('整理要求'),
            ),
          if (widget.step == OrganizerStep.preview)
            const FBreadcrumbItem(current: true, child: Text('修改预览')),
        ],
      ),
    ],
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
          ? '正在执行重命名'
          : state.message.isEmpty
          ? '正在处理…'
          : state.message;
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
                    state.progress,
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
      title: Text(state.message),
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
      crumbs.add(('根目录', root));
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
    final sorted = [...state.entries]
      ..sort(
        (a, b) => a.directory != b.directory
            ? (a.directory ? -1 : 1)
            : a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    final visible = query.isEmpty
        ? sorted
        : sorted.where((e) => e.name.toLowerCase().contains(query)).toList();
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
                          Text('NAS 目录', style: theme.typography.body.lg),
                          if (connected)
                            Text(
                              '$folders 个文件夹 · $files 个文件',
                              style: theme.typography.body.xs.copyWith(
                                color: theme.colors.mutedForeground,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    FButton(
                      variant: connected ? .outline : .primary,
                      size: .sm,
                      mainAxisSize: MainAxisSize.min,
                      onPress: locked
                          ? null
                          : connected
                          ? _controller.disconnect
                          : () => _controller.open(null),
                      prefix: Icon(
                        connected ? FLucideIcons.unplug : FLucideIcons.plugZap,
                      ),
                      child: Text(connected ? '断开连接' : '连接 NAS'),
                    ),
                  ],
                ),
              ),
              if (connected) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: (box.maxWidth - 40).clamp(0, double.infinity),
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FBreadcrumb(
                          children: [
                            for (final (index, (label, path)) in crumbs.indexed)
                              FBreadcrumbItem(
                                current: index == crumbs.length - 1,
                                onPress: locked || index == crumbs.length - 1
                                    ? null
                                    : () => _controller.open(path),
                                child: Text(label),
                              ),
                          ],
                        ),
                      ),
                    ),
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
                      hint: '按名称筛选',
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
                child: ClipRect(
                  child: ListView.builder(
                    key: const ValueKey('nas-file-list'),
                    primary: false,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: !connected || visible.isEmpty
                        ? 1
                        : visible.length,
                    itemBuilder: (context, index) {
                      if (!connected) {
                        return const _Placeholder(
                          icon: FLucideIcons.hardDrive,
                          message: '连接 NAS 后，在这里浏览并打开要整理的剧集目录。',
                        );
                      }
                      if (state.entries.isEmpty) {
                        return const _Placeholder(
                          icon: FLucideIcons.folderOpen,
                          message: '此目录为空',
                        );
                      }
                      if (visible.isEmpty) {
                        return _Placeholder(
                          icon: FLucideIcons.search,
                          message: '没有名称包含“${filter.text.trim()}”的项目',
                        );
                      }
                      final entry = visible[index];
                      return _EntryRow(
                        key: ValueKey(entry.path),
                        entry: entry,
                        locked: locked,
                        compact: compact,
                        planned: planned.contains(entry.path),
                        onOpen: () => _controller.open(entry.path),
                      );
                    },
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
    final hasFiles = state.entries.any((e) => !e.directory);
    final canPropose = !locked && state.directory.isNotEmpty && hasFiles;
    final hint = state.directory.isEmpty
        ? '请先连接 NAS 并打开剧集所在目录。'
        : !hasFiles
        ? '当前目录没有文件，请打开包含剧集文件的目录。'
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
              Expanded(child: Text('AI 整理建议', style: theme.typography.body.lg)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            displayDavPath(state.directory),
            style: theme.typography.body.sm,
          ),
          const SizedBox(height: 16),
          FTextField(
            control: .managed(controller: instruction),
            label: const Text('整理要求（可选）'),
            hint: '剧名、季数、TMDB ID 或命名偏好',
            enabled: !locked,
            onSubmit: canPropose ? (_) => _propose() : null,
          ),
          const SizedBox(height: 12),
          FButton(
            prefix: const Icon(FLucideIcons.sparkles),
            onPress: canPropose ? _propose : null,
            child: const Text('AI 生成重命名建议'),
          ),
          if (state.plan.isNotEmpty) ...[
            const SizedBox(height: 12),
            FButton(
              variant: .outline,
              onPress: locked
                  ? null
                  : () => context.go('/organize/assistant/preview'),
              child: const Text('查看修改预览'),
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
                Text('修改预览', style: theme.typography.body.lg),
              ],
            ),
            const SizedBox(height: 6),
            Text('暂无待执行的修改', style: muted),
            const SizedBox(height: 12),
            FButton(
              variant: .outline,
              onPress: locked ? null : () => context.go('/organize/assistant'),
              child: const Text('返回整理要求'),
            ),
          ],
        ),
      );
    }
    final error = validatePlan(state.plan, state.entries);
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
                      Text('修改预览', style: theme.typography.body.lg),
                      Text(
                        '已选 $selected / ${state.plan.length} 项 · $changes 项将被修改',
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
                  child: Text(allSelected ? '全不选' : '全选'),
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
              entries: state.entries,
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
                title: const Text('暂时无法执行'),
                subtitle: Text(error),
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
      ('输入 Tok', available ? '${usage.inputTokens}' : '—'),
      ('输出 Tok', available ? '${usage.outputTokens}' : '—'),
      ('平均 TPS', tps?.toStringAsFixed(1) ?? '—'),
      ('预估花费', cost == null ? '—' : '\$${cost.toStringAsFixed(6)}'),
    ];
    return Surface(
      padding: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('AI 分析用量', style: theme.typography.body.lg),
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
            ],
          ),
        ],
      ),
    );
  }
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
        child: const Text('取消'),
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
    required this.onOpen,
    super.key,
  });
  final DavEntry entry;
  final bool locked, compact, planned;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final details = [
      if (entry.directory) '文件夹',
      if (!entry.directory && entry.size != null) _formatSize(entry.size!),
      if (!compact || entry.directory) ?_formatModified(entry.modified),
    ].join(' · ');
    return FTappable(
      onPress: entry.directory && !locked ? onOpen : null,
      semanticsLabel: entry.directory ? '打开 ${entry.name}' : entry.name,
      builder: (context, variants, child) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color:
              entry.directory &&
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
              FBadge(variant: .secondary, child: Text(compact ? '待改' : '待重命名')),
            ],
            const SizedBox(width: 4),
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
    final original = Uri.decodeComponent(item.source.split('/').last);
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
                        FBadge(variant: .outline, child: const Text('未变化')),
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
                    hint: '新文件名',
                  ),
                  if (issue != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      issue,
                      style: theme.typography.body.xs.copyWith(
                        color: theme.colors.destructive,
                      ),
                    ),
                  ],
                  if (item.reason.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      item.reason,
                      style: theme.typography.body.xs.copyWith(
                        color: theme.colors.mutedForeground,
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
