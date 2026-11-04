import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../shared/localization.dart';
import '../../../shared/runtime_localization.dart';
import '../../../shared/widgets.dart';
import '../connections/connection_settings.dart';
import '../connections/http_clients.dart';
import '../organizer_state.dart';
import 'directory_breadcrumb.dart';
import 'directory_favorites.dart';
import 'directory_favorites_bar.dart';
import 'webdav.dart';

Future<String?> showDirectoryPicker(
  BuildContext context, {
  required ConnectionSettings connection,
  required String directory,
}) {
  Widget picker() => EscapeDismiss(
    child: _DirectoryPicker(connection: connection, directory: directory),
  );
  if (MediaQuery.sizeOf(context).width < 600) {
    return showFSheet<String>(
      context: context,
      side: .btt,
      useSafeArea: true,
      mainAxisMaxRatio: .9,
      builder: (_) => picker(),
    );
  }
  return showFDialog<String>(
    context: context,
    useSafeArea: true,
    builder: (context, style, animation) => FDialog(
      animation: animation,
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 560),
      builder: (_, _) => picker(),
    ),
  );
}

class _DirectoryPicker extends ConsumerStatefulWidget {
  const _DirectoryPicker({required this.connection, required this.directory});

  final ConnectionSettings connection;
  final String directory;

  @override
  ConsumerState<_DirectoryPicker> createState() => _DirectoryPickerState();
}

class _DirectoryPickerState extends ConsumerState<_DirectoryPicker> {
  final _filter = TextEditingController();
  WebDavClient? _client;
  String _directory = '';
  String _requested = '';
  List<DavEntry> _folders = const [];
  String? _error;
  bool _loading = true;
  bool _savingFavorite = false;

  bool get _desktop => switch (defaultTargetPlatform) {
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => true,
    _ => false,
  };

  String? get _parent {
    final root = _client?.root;
    return _directory.isEmpty || _directory == root
        ? null
        : _directory.replaceFirst(RegExp(r'[^/]+/$'), '');
  }

  Future<void> _favorites() async {
    final path = await showDirectoryFavoritesDialog(
      context,
      scope: nasScope(widget.connection),
      directory: _directory,
    );
    if (mounted && path != null) await _open(path);
  }

  Future<void> _toggleFavorite({required bool selected}) async {
    if (_savingFavorite) return;
    final scope = nasScope(widget.connection);
    final directory = _directory;
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

  @override
  void initState() {
    super.initState();
    _open(widget.directory);
  }

  @override
  void dispose() {
    _client?.close();
    _filter.dispose();
    super.dispose();
  }

  Future<void> _open(String path) async {
    setState(() {
      _loading = true;
      _error = null;
      _requested = path;
    });
    try {
      final client = _client ??= ref.read(webDavFactoryProvider)(
        widget.connection,
      );
      final directory = path.isEmpty
          ? client.root
          : client.normalize(path.endsWith('/') ? path : '$path/');
      final entries = await client.list(directory);
      if (!mounted) return;
      setState(() {
        _directory = directory;
        _folders = entries.where((entry) => entry.directory).toList()
          ..sort((a, b) => a.name.compareTo(b.name));
        _filter.clear();
      });
    } catch (error) {
      if (mounted) setState(() => _error = serviceError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(connectionSettingsProvider, (previous, next) {
      if (!identical(next.asData?.value, widget.connection)) {
        Navigator.of(context).pop();
      }
    });
    final l = context.l10n;
    final root = _client?.root;
    final paths = ref
        .watch(directoryFavoritesProvider(nasScope(widget.connection)))
        .asData
        ?.value;
    final selected = paths?.contains(_directory) ?? false;
    final parent = _parent;
    final query = _filter.text.trim().toLowerCase();
    final visible = _folders
        .where((entry) => entry.name.toLowerCase().contains(query))
        .toList();
    final content = ColoredBox(
      color: context.theme.colors.background,
      child: SizedBox(
        key: const ValueKey('directory-picker'),
        height: 560,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.selectDirectory, style: context.theme.typography.body.lg),
              const SizedBox(height: 16),
              Row(
                children: [
                  FButton.icon(
                    key: const ValueKey('directory-picker-root'),
                    variant: .outline,
                    size: .sm,
                    semanticsLabel: l.rootDirectory,
                    onPress: _loading || root == null || _directory == root
                        ? null
                        : () => _open(root),
                    child: const Icon(FLucideIcons.house),
                  ),
                  const SizedBox(width: 8),
                  FButton.icon(
                    key: const ValueKey('directory-picker-parent'),
                    variant: .outline,
                    size: .sm,
                    semanticsLabel: l.parentDirectory,
                    onPress: _loading || parent == null
                        ? null
                        : () => _open(parent),
                    child: const Icon(FLucideIcons.arrowUp),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: root == null
                        ? const SizedBox.shrink()
                        : DirectoryBreadcrumb(
                            key: const ValueKey('directory-picker-path'),
                            directory: _directory,
                            root: root,
                            locked: _loading,
                            onOpen: _open,
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FTextField(
                key: const ValueKey('directory-picker-filter'),
                enabled: !_loading,
                hint: l.filterByName,
                control: .managed(
                  controller: _filter,
                  onChange: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _loading
                    ? const Center(child: FCircularProgress())
                    : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(localizeRuntimeMessage(l, _error!)),
                            const SizedBox(height: 12),
                            FButton(
                              variant: .outline,
                              onPress: () => _open(_requested),
                              child: Text(l.retry),
                            ),
                          ],
                        ),
                      )
                    : visible.isEmpty
                    ? EmptyState(
                        query.isEmpty ? l.noSubdirectories : l.noNameMatches,
                        icon: query.isEmpty
                            ? FLucideIcons.folderOpen
                            : FLucideIcons.search,
                      )
                    : ListView.builder(
                        primary: false,
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final entry = visible[index];
                          return FItem(
                            key: ValueKey(
                              'directory-picker-folder-${entry.path}',
                            ),
                            prefix: const Icon(FLucideIcons.folder),
                            title: Text(
                              entry.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            suffix: const Icon(FLucideIcons.chevronRight),
                            onPress: () => _open(entry.path),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FTooltip(
                        tipBuilder: (_, _) => Text(l.favorites),
                        child: FButton.icon(
                          key: const ValueKey('directory-picker-favorites'),
                          variant: .outline,
                          size: .sm,
                          semanticsLabel: l.favorites,
                          onPress: _loading || _savingFavorite
                              ? null
                              : _favorites,
                          child: const Icon(FLucideIcons.list),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FTooltip(
                        tipBuilder: (_, _) => Text(
                          selected
                              ? l.unfavoriteDirectory
                              : l.favoriteDirectory,
                        ),
                        child: FButton.icon(
                          key: const ValueKey('directory-picker-favorite'),
                          variant: selected ? .primary : .outline,
                          size: .sm,
                          semanticsLabel: selected
                              ? l.unfavoriteDirectory
                              : l.favoriteDirectory,
                          onPress:
                              _loading ||
                                  _savingFavorite ||
                                  _error != null ||
                                  _directory.isEmpty ||
                                  paths == null
                              ? null
                              : () => _toggleFavorite(selected: selected),
                          child: const Icon(FLucideIcons.star),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FButton(
                        variant: .outline,
                        mainAxisSize: MainAxisSize.min,
                        onPress: () => Navigator.of(context).pop(),
                        child: Text(l.cancel),
                      ),
                      const SizedBox(width: 12),
                      FButton(
                        key: const ValueKey('directory-picker-confirm'),
                        mainAxisSize: MainAxisSize.min,
                        onPress:
                            _loading || _error != null || _directory.isEmpty
                            ? null
                            : () => Navigator.of(context).pop(_directory),
                        child: Text(l.selectCurrentDirectory),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _desktop
          ? (event) {
              if (event.kind == PointerDeviceKind.mouse &&
                  event.buttons & kBackMouseButton != 0 &&
                  !_loading &&
                  _parent != null) {
                _open(_parent!);
              }
            }
          : null,
      child: content,
    );
  }
}
