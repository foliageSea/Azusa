import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../shared/widgets.dart';
import '../../../shared/localization.dart';
import 'dav_paths.dart';
import 'directory_favorites.dart';

Future<String?> showDirectoryFavoritesDialog(
  BuildContext context, {
  required NasScope scope,
  required String directory,
}) => showFDialog<String>(
  context: context,
  builder: (context, style, animation) => FDialog(
    animation: animation,
    builder: (_, _) => EscapeDismiss(
      child: _FavoritesDialog(scope: scope, directory: directory),
    ),
  ),
);

class _FavoritesDialog extends ConsumerStatefulWidget {
  const _FavoritesDialog({required this.scope, required this.directory});
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
    final current = widget.directory.isEmpty
        ? null
        : favoriteDirectory(widget.directory);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.l10n.favorites, style: context.theme.typography.body.lg),
          const SizedBox(height: 16),
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
                                      variant: path == current
                                          ? .secondary
                                          : .outline,
                                      builder: (_, _, _, _, _, child) =>
                                          Expanded(child: child!),
                                      onPress: saving
                                          ? null
                                          : () =>
                                                Navigator.of(context).pop(path),
                                      child: Text(
                                        displayDavPath(path),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  FButton.icon(
                                    variant: .destructive,
                                    size: .sm,
                                    semanticsLabel: context.l10n.removeFavorite(
                                      displayDavPath(path),
                                    ),
                                    onPress: saving
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
