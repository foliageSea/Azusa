import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../shared/widgets.dart';
import '../../../shared/localization.dart';
import '../organizer_state.dart';
import 'dav_paths.dart';
import 'directory_favorites.dart';

class DirectoryFavoritesButton extends StatelessWidget {
  const DirectoryFavoritesButton({
    required this.scope,
    required this.directory,
    required this.locked,
    required this.onOpen,
    super.key,
  });
  final NasScope scope;
  final String directory;
  final bool locked;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    Widget trigger(VoidCallback open) => FTooltip(
      tipBuilder: (_, _) => Text(context.l10n.favorites),
      child: FButton.icon(
        variant: .outline,
        semanticsLabel: context.l10n.favorites,
        onPress: locked ? null : open,
        child: const Icon(FLucideIcons.list),
      ),
    );
    if (MediaQuery.sizeOf(context).width < 600) {
      return trigger(() async {
        final path = await showFSheet<String>(
          context: context,
          side: .btt,
          useSafeArea: true,
          mainAxisMaxRatio: .75,
          builder: (context) => _FavoritesDialog(
            scope: scope,
            directory: directory,
            onOpen: (path) => Navigator.of(context).pop(path),
          ),
        );
        if (context.mounted && path != null) onOpen(path);
      });
    }
    return FPopover(
      popoverAnchor: Alignment.bottomLeft,
      childAnchor: Alignment.topLeft,
      popoverBuilder: (_, controller) => Container(
        width: 340,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: context.theme.style.borderRadius.md,
        ),
        foregroundDecoration: BoxDecoration(
          border: Border.all(color: context.theme.colors.border),
          borderRadius: context.theme.style.borderRadius.md,
        ),
        child: _FavoritesDialog(
          scope: scope,
          directory: directory,
          onOpen: (path) async {
            await controller.hide();
            if (context.mounted) onOpen(path);
          },
        ),
      ),
      builder: (_, controller, _) => trigger(controller.toggle),
    );
  }
}

class _FavoritesDialog extends ConsumerStatefulWidget {
  const _FavoritesDialog({
    required this.scope,
    required this.directory,
    required this.onOpen,
  });
  final ValueChanged<String> onOpen;
  final NasScope scope;
  final String directory;

  @override
  ConsumerState<_FavoritesDialog> createState() => _FavoritesDialogState();
}

class _FavoritesDialogState extends ConsumerState<_FavoritesDialog> {
  bool saving = false;
  String? error;

  Future<void> _remove(String path) async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final repository = ref.read(directoryFavoritesRepositoryProvider);
      await repository.remove(widget.scope, path);
      if (mounted) ref.invalidate(directoryFavoritesProvider(widget.scope));
    } catch (_) {
      if (mounted) setState(() => error = context.l10n.favoriteSaveFailed);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = directoryFavoritesProvider(widget.scope);
    final favorites = ref.watch(provider);
    final organizer = ref.watch(organizerProvider);
    final locked = saving || organizer.busy || organizer.executing;
    final current = widget.directory.isEmpty
        ? null
        : favoriteDirectory(widget.directory);
    return Container(
      key: const ValueKey('directory-favorites-panel'),
      color: context.theme.colors.background,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .65,
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
            child: Text(
              context.l10n.favorites,
              style: context.theme.typography.body.sm.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (error != null) ...[Text(error!), const SizedBox(height: 12)],
          Flexible(
            child: favorites.when(
              loading: () => Text(context.l10n.loading),
              error: (_, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(context.l10n.favoritesLoadFailed),
                  FButton(
                    variant: .outline,
                    onPress: () => ref.invalidate(provider),
                    child: Text(context.l10n.retry),
                  ),
                ],
              ),
              data: (items) => items.isEmpty
                  ? EmptyState(
                      context.l10n.noFavorites,
                      icon: FLucideIcons.star,
                    )
                  : SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final path in items)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: FButton(
                                      variant: .ghost,
                                      semanticsLabel: displayDavPath(path),
                                      prefix: Icon(
                                        FLucideIcons.folder,
                                        color: path == current
                                            ? context.theme.colors.primary
                                            : context
                                                  .theme
                                                  .colors
                                                  .mutedForeground,
                                      ),
                                      suffix: path == current
                                          ? Icon(
                                              FLucideIcons.check,
                                              color:
                                                  context.theme.colors.primary,
                                              size: 16,
                                            )
                                          : null,
                                      builder: (_, _, _, _, _, child) =>
                                          Expanded(child: child!),
                                      onPress: locked
                                          ? null
                                          : () => widget.onOpen(path),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            Uri.decodeComponent(
                                              path
                                                      .split('/')
                                                      .where(
                                                        (part) =>
                                                            part.isNotEmpty,
                                                      )
                                                      .lastOrNull ??
                                                  '/',
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            displayDavPath(path),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: context
                                                .theme
                                                .typography
                                                .body
                                                .xs
                                                .copyWith(
                                                  color: context
                                                      .theme
                                                      .colors
                                                      .mutedForeground,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  FButton.icon(
                                    variant: .ghost,
                                    size: .sm,
                                    semanticsLabel: context.l10n.removeFavorite(
                                      displayDavPath(path),
                                    ),
                                    onPress: locked
                                        ? null
                                        : () => _remove(path),
                                    child: const Icon(FLucideIcons.x, size: 16),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
