import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../shared/widgets.dart';
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
      if (mounted) setState(() => error = '保存收藏失败，请重试');
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
          Text('收藏列表', style: context.theme.typography.body.lg),
          const SizedBox(height: 16),
          if (error != null) ...[Text(error!), const SizedBox(height: 12)],
          Flexible(
            child: favorites.when(
              loading: () => const Text('加载中…'),
              error: (_, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('读取收藏失败'),
                  FButton(
                    variant: .outline,
                    onPress: () => ref.invalidate(provider),
                    child: const Text('重试'),
                  ),
                ],
              ),
              data: (items) => items.isEmpty
                  ? const Text('暂无收藏目录')
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
                                    semanticsLabel:
                                        '移除收藏 ${displayDavPath(path)}',
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
