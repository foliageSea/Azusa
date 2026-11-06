import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../shared/localization.dart';
import '../../shared/responsive_button.dart';
import '../organizer/dav/dav_paths.dart';
import '../organizer/organizer_state.dart';

class SelectedDirectoriesButton extends StatelessWidget {
  const SelectedDirectoriesButton({required this.onAdd, super.key});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 600;
    if (mobile) {
      return _DirectoryButton(
        onPress: () => showFSheet<void>(
          context: context,
          side: .btt,
          builder: (context) => SafeArea(
            top: false,
            child: _DirectoryPanel(
              onClose: () => Navigator.of(context).pop(),
              onAdd: onAdd,
            ),
          ),
        ),
      );
    }
    return FPopover(
      popoverAnchor: Alignment.topRight,
      childAnchor: Alignment.bottomRight,
      popoverBuilder: (context, controller) => SizedBox(
        width: 460,
        child: _DirectoryPanel(onClose: () => controller.hide(), onAdd: onAdd),
      ),
      builder: (_, controller, _) =>
          _DirectoryButton(onPress: controller.toggle),
    );
  }
}

class _DirectoryButton extends ConsumerWidget {
  const _DirectoryButton({required this.onPress});
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(organizerProvider);
    final label = context.l10n.selectedDirectoryCount(
      state.selectedDirectories.length,
    );
    return FButton(
      key: const ValueKey('assistant-directory'),
      variant: .outline,
      size: .sm,
      mainAxisSize: MainAxisSize.min,
      builder: responsiveButtonContent,
      semanticsLabel: label,
      prefix: const Icon(FLucideIcons.folderOpen),
      suffix: const Icon(FLucideIcons.chevronDown),
      onPress: onPress,
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

class _DirectoryPanel extends ConsumerWidget {
  const _DirectoryPanel({required this.onClose, required this.onAdd});
  final VoidCallback onClose, onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(organizerProvider);
    final controller = ref.read(organizerProvider.notifier);
    final locked = state.busy || state.executing;
    final theme = context.theme;
    final l = context.l10n;
    final groups = <String, List<String>>{};
    for (final path in state.selectedDirectories) {
      final trimmed = path.substring(0, path.length - 1);
      final parent = trimmed.substring(0, trimmed.lastIndexOf('/') + 1);
      groups.putIfAbsent(parent, () => []).add(path);
    }
    return ConstrainedBox(
      key: const ValueKey('selected-directories-panel'),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .65,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.selectedDirectoryCount(state.selectedDirectories.length),
              style: theme.typography.body.md.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                key: const ValueKey('selected-directories-list'),
                shrinkWrap: true,
                primary: false,
                children: [
                  for (final group in groups.entries) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                      child: Text(
                        displayDavPath(group.key),
                        style: theme.typography.body.xs.copyWith(
                          color: theme.colors.mutedForeground,
                        ),
                      ),
                    ),
                    for (final path in group.value)
                      _DirectoryRow(
                        key: ValueKey(path),
                        path: path,
                        onRemove: locked
                            ? null
                            : () {
                                if (state.selectedDirectories.length == 1) {
                                  onClose();
                                }
                                controller.toggleDirectory(path);
                              },
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FButton(
                    variant: .outline,
                    size: .sm,
                    prefix: const Icon(FLucideIcons.folderPlus),
                    onPress: locked
                        ? null
                        : () {
                            onClose();
                            onAdd();
                          },
                    child: Text(l.addDirectories),
                  ),
                ),
                const SizedBox(width: 8),
                FButton(
                  variant: .ghost,
                  size: .sm,
                  onPress: locked
                      ? null
                      : () {
                          onClose();
                          controller.selectDirectories([]);
                        },
                  child: Text(l.clearDirectorySelection),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DirectoryRow extends StatefulWidget {
  const _DirectoryRow({required this.path, required this.onRemove, super.key});
  final String path;
  final VoidCallback? onRemove;

  @override
  State<_DirectoryRow> createState() => _DirectoryRowState();
}

class _DirectoryRowState extends State<_DirectoryRow> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final name = Uri.decodeComponent(
      widget.path.split('/').where((part) => part.isNotEmpty).lastOrNull ?? '/',
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            FLucideIcons.folder,
            size: 18,
            color: theme.colors.mutedForeground,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FTooltip(
              tipBuilder: (_, _) => Text(displayDavPath(widget.path)),
              child: FTappable(
                onPress: () => setState(() => expanded = !expanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    expanded ? displayDavPath(widget.path) : name,
                    maxLines: expanded ? null : 2,
                    overflow: expanded ? null : TextOverflow.ellipsis,
                    style: theme.typography.body.sm,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FButton.icon(
            key: ValueKey('remove-directory-${widget.path}'),
            variant: .ghost,
            size: .sm,
            semanticsLabel: context.l10n.removeSelectedDirectory(name),
            onPress: widget.onRemove,
            child: const Icon(FLucideIcons.x, size: 16),
          ),
        ],
      ),
    );
  }
}
