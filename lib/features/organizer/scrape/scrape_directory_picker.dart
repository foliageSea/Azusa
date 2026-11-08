import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../shared/localization.dart';
import '../../../shared/responsive_button.dart';
import '../dav/dav_paths.dart';
import '../organizer_state.dart';

/// Returns an immutable snapshot, without changing the main browser's state.
Future<List<String>?> showScrapeDirectoryPicker(
  BuildContext context, {
  bool cleanup = false,
}) => showFDialog<List<String>>(
  context: context,
  builder: (context, style, animation) => FDialog(
    animation: animation,
    builder: (context, style) => _ScrapeDirectoryPicker(cleanup: cleanup),
  ),
);

class _ScrapeDirectoryPicker extends ConsumerStatefulWidget {
  const _ScrapeDirectoryPicker({required this.cleanup});

  final bool cleanup;

  @override
  ConsumerState<_ScrapeDirectoryPicker> createState() =>
      _ScrapeDirectoryPickerState();
}

class _ScrapeDirectoryPickerState
    extends ConsumerState<_ScrapeDirectoryPicker> {
  final _selected = <String>{};

  @override
  void initState() {
    super.initState();
    final state = ref.read(organizerProvider);
    _selected.addAll(
      state.selectedDirectories.isNotEmpty
          ? state.selectedDirectories
          : [if (state.directory.isNotEmpty) state.directory],
    );
  }

  void _toggle(String path, bool selected) => setState(() {
    selected ? _selected.add(path) : _selected.remove(path);
  });

  final _expandedPaths = <String>{};

  String _name(String path) => Uri.decodeComponent(
    path.split('/').where((part) => part.isNotEmpty).lastOrNull ?? '/',
  );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = context.theme;
    final secondary = theme.typography.body.sm.copyWith(
      color: theme.colors.mutedForeground,
    );
    final compact = MediaQuery.sizeOf(context).width < 600;
    final selected = _selected.toList();
    return Padding(
      padding: EdgeInsets.all(compact ? 16 : 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: MediaQuery.sizeOf(context).height * .8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.cleanup ? l.cleanScrapedFiles : l.scrapeMetadata,
              style: theme.typography.body.lg.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            Text(l.selectedDirectoryCount(selected.length), style: secondary),
            if (selected.isNotEmpty) ...[
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .5,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  primary: false,
                  itemCount: selected.length,
                  itemBuilder: (context, index) {
                    final path = selected[index];
                    final expanded = _expandedPaths.contains(path);
                    return Row(
                      children: [
                        Icon(
                          FLucideIcons.folder,
                          size: 16,
                          color: theme.colors.mutedForeground,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FTappable(
                            key: ValueKey('scrape-selected-path:$path'),
                            onPress: () => setState(() {
                              expanded
                                  ? _expandedPaths.remove(path)
                                  : _expandedPaths.add(path);
                            }),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                expanded ? displayDavPath(path) : _name(path),
                                maxLines: expanded ? null : 1,
                                overflow: expanded
                                    ? null
                                    : TextOverflow.ellipsis,
                                style: theme.typography.body.sm,
                              ),
                            ),
                          ),
                        ),
                        FButton.icon(
                          key: ValueKey('scrape-remove:$path'),
                          variant: .ghost,
                          size: .sm,
                          semanticsLabel: l.removeSelectedDirectory(
                            displayDavPath(path),
                          ),
                          onPress: () => _toggle(path, false),
                          child: const Icon(FLucideIcons.x, size: 16),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FButton(
                    builder: responsiveButtonContent,
                    variant: .outline,
                    onPress: () => Navigator.of(context).pop(),
                    child: Text(l.cancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FButton(
                    builder: responsiveButtonContent,
                    key: const ValueKey('scrape-start-scan'),
                    onPress: _selected.isEmpty
                        ? null
                        : () =>
                              Navigator.of(context)
                                  .pop(List<String>.unmodifiable(_selected)),
                    child: Text(l.scrapeStartScan),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
