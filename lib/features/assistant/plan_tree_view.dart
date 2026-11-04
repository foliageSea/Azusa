import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../shared/localization.dart';
import '../../shared/responsive_button.dart';
import '../../shared/runtime_localization.dart';
import '../../shared/widgets.dart';
import '../organizer/dav/dav_paths.dart';
import '../organizer/dav/webdav.dart';
import '../organizer/rename_plan.dart';
import 'plan_tree.dart';

class PlanTreeView extends StatefulWidget {
  const PlanTreeView({
    required this.tree,
    required this.entries,
    required this.disabled,
    required this.onName,
    required this.onEnabled,
    super.key,
  });

  final PlanTree tree;
  final List<DavEntry> entries;
  final bool disabled;
  final void Function(int index, String name) onName;
  final void Function(int index, bool enabled) onEnabled;

  @override
  State<PlanTreeView> createState() => _PlanTreeViewState();
}

class _PlanTreeViewState extends State<PlanTreeView> {
  final _collapsed = <String>{};
  final _expandedFiles = <String>{};

  @override
  void didUpdateWidget(covariant PlanTreeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tree.root.path != widget.tree.root.path) {
      _collapsed.clear();
      _expandedFiles.clear();
    }
  }

  void _toggle(Set<String> paths, String path) => setState(() {
    if (!paths.remove(path)) paths.add(path);
  });

  @override
  Widget build(BuildContext context) {
    final rows = <(PlanTreeNode, int)>[];
    void visit(PlanTreeNode node, int depth) {
      rows.add((node, depth));
      if (node is PlanTreeDirectory && !_collapsed.contains(node.path)) {
        for (final child in node.children) {
          visit(child, depth + 1);
        }
      }
    }

    visit(widget.tree.root, 0);
    return LayoutBuilder(
      builder: (context, box) => ListView.builder(
        key: const ValueKey('assistant-plan-list'),
        primary: false,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final (node, depth) = rows[index];
          final indent = (depth * 16.0).clamp(0.0, box.maxWidth * .25);
          final child = switch (node) {
            PlanTreeDirectory() => _DirectoryRow(
              key: ValueKey('plan-folder-${node.path}'),
              node: node,
              expanded: !_collapsed.contains(node.path),
              isNew: widget.tree.newDirectories.contains(node.path),
              onToggle: () => _toggle(_collapsed, node.path),
            ),
            PlanTreeFile() => _FileRow(
              key: ValueKey('assistant-row-${node.item.source}'),
              node: node,
              expanded: _expandedFiles.contains(node.item.source),
              entries: widget.entries,
              disabled: widget.disabled,
              onToggle: () => _toggle(_expandedFiles, node.item.source),
              onName: (name) => widget.onName(node.index, name),
              onEnabled: (value) => widget.onEnabled(node.index, value),
            ),
          };
          return Padding(
            key: ValueKey(node is PlanTreeFile ? node.item.source : node.path),
            padding: EdgeInsets.only(left: indent),
            child: child,
          );
        },
      ),
    );
  }
}

class _DirectoryRow extends StatelessWidget {
  const _DirectoryRow({
    required this.node,
    required this.expanded,
    required this.isNew,
    required this.onToggle,
    super.key,
  });

  final PlanTreeDirectory node;
  final bool expanded, isNew;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return FTappable(
      semanticsLabel: node.name,
      semanticsExpanded: expanded,
      onPress: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: Row(
          children: [
            Icon(
              expanded ? FLucideIcons.chevronDown : FLucideIcons.chevronRight,
              size: 14,
              color: theme.colors.mutedForeground,
            ),
            const SizedBox(width: 6),
            Icon(
              expanded ? FLucideIcons.folderOpen : FLucideIcons.folder,
              size: 17,
              color: isNew
                  ? theme.colors.primary
                  : theme.colors.mutedForeground,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                node.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.typography.body.sm.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (isNew) ...[
              const SizedBox(width: 8),
              FBadge(
                variant: .outline,
                child: Text(context.l10n.newFolderBadge),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.node,
    required this.expanded,
    required this.entries,
    required this.disabled,
    required this.onToggle,
    required this.onName,
    required this.onEnabled,
    super.key,
  });

  final PlanTreeFile node;
  final bool expanded, disabled;
  final List<DavEntry> entries;
  final VoidCallback onToggle;
  final ValueChanged<String> onName;
  final ValueChanged<bool> onEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final item = node.item;
    final issue = item.enabled ? validatePlan([item], entries) : null;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: item.enabled ? 1 : .55,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: FCheckbox(
                  key: ValueKey('plan-select-${item.source}'),
                  semanticsLabel: item.targetName,
                  value: item.enabled,
                  enabled: !disabled,
                  onChange: onEnabled,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FTappable(
                  key: ValueKey('plan-file-${item.source}'),
                  semanticsExpanded: expanded,
                  onPress: onToggle,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        Icon(
                          issue == null
                              ? FLucideIcons.fileVideoCamera
                              : FLucideIcons.circleAlert,
                          size: 16,
                          color: issue == null
                              ? theme.colors.mutedForeground
                              : theme.colors.destructive,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.targetName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.typography.body.sm,
                          ),
                        ),
                        if (item.source == item.target) ...[
                          const SizedBox(width: 6),
                          Icon(
                            FLucideIcons.check,
                            size: 14,
                            semanticLabel: context.l10n.unchanged,
                            color: theme.colors.mutedForeground,
                          ),
                        ],
                        const SizedBox(width: 6),
                        Icon(
                          expanded
                              ? FLucideIcons.chevronUp
                              : FLucideIcons.chevronDown,
                          size: 14,
                          color: theme.colors.mutedForeground,
                        ),
                        const SizedBox(width: 6),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (expanded)
            _FileDetails(
              item: item,
              issue: issue,
              disabled: disabled,
              onName: onName,
            ),
        ],
      ),
    );
  }
}

class _FileDetails extends StatefulWidget {
  const _FileDetails({
    required this.item,
    required this.issue,
    required this.disabled,
    required this.onName,
  });

  final RenameItem item;
  final String? issue;
  final bool disabled;
  final ValueChanged<String> onName;

  @override
  State<_FileDetails> createState() => _FileDetailsState();
}

class _FileDetailsState extends State<_FileDetails> {
  late final _name = TextEditingController(text: widget.item.targetName);

  @override
  void didUpdateWidget(covariant _FileDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_name.text != widget.item.targetName) {
      _name.text = widget.item.targetName;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = context.theme;
    final item = widget.item;
    final muted = theme.typography.body.xs.copyWith(
      color: theme.colors.mutedForeground,
    );
    return Container(
      margin: const EdgeInsets.only(left: 6, right: 6, bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colors.secondary.withValues(alpha: .4),
        borderRadius: theme.style.borderRadius.md,
        border: Border.all(color: theme.colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (item.mediaTitle case final title?) ...[
            Text(title, style: theme.typography.body.sm),
            const SizedBox(height: 4),
            Text(
              [
                switch (item.tmdbMediaType) {
                  TmdbMediaType.movie => l.movieLabel,
                  TmdbMediaType.tv => l.seriesLabel,
                  null => null,
                },
                if (item.seasonNumber case final season?) l.seasonLabel(season),
              ].nonNulls.join(' · '),
              style: muted,
            ),
            const SizedBox(height: 12),
          ],
          Text(l.originalPath, style: muted),
          const SizedBox(height: 4),
          Text(displayDavPath(item.source), style: muted),
          const SizedBox(height: 12),
          FTextField(
            key: ValueKey('plan-name-${item.source}'),
            label: Text(l.newFileName),
            control: .managed(
              controller: _name,
              onChange: (value) => widget.onName(value.text),
            ),
            enabled: !widget.disabled,
          ),
          const SizedBox(height: 12),
          Text(l.newPath, style: muted),
          const SizedBox(height: 4),
          Text(displayDavPath(item.target), style: muted),
          if (widget.issue case final issue?) ...[
            const SizedBox(height: 8),
            Text(
              localizeRuntimeMessage(l, issue),
              style: muted.copyWith(color: theme.colors.destructive),
            ),
          ],
          if (item.reason.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(localizeRuntimeMessage(l, item.reason), style: muted),
          ],
          if (item.tmdbUrl case final url?) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FButton(
                key: ValueKey('tmdb-link-${item.source}'),
                variant: .ghost,
                size: .sm,
                mainAxisSize: MainAxisSize.min,
                builder: responsiveButtonContent,
                prefix: const Icon(FLucideIcons.externalLink),
                onPress: () => openDocumentation(context, url.toString()),
                child: Text(l.viewOnTmdb),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
