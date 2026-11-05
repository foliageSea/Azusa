import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../shared/localization.dart';
import '../../../shared/runtime_localization.dart';
import '../organizer_state.dart';
import 'dav_paths.dart';

class EmptyDirectoryButton extends ConsumerWidget {
  const EmptyDirectoryButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(organizerProvider);
    void open() => showFDialog<void>(
      context: context,
      builder: (context, style, animation) => FDialog(
        animation: animation,
        builder: (context, style) => const _EmptyDirectoryDialog(),
      ),
    );
    final locked = state.busy || state.executing || state.directory.isEmpty;
    return FButton(
      key: const ValueKey('empty-directory-cleanup'),
      variant: .outline,
      size: .sm,
      mainAxisSize: MainAxisSize.min,
      prefix: const Icon(FLucideIcons.folderMinus),
      onPress: locked ? null : open,
      child: Text(context.l10n.cleanEmptyDirectories),
    );
  }
}

class _EmptyDirectoryDialog extends ConsumerStatefulWidget {
  const _EmptyDirectoryDialog();

  @override
  ConsumerState<_EmptyDirectoryDialog> createState() =>
      _EmptyDirectoryDialogState();
}

class _EmptyDirectoryDialogState extends ConsumerState<_EmptyDirectoryDialog> {
  List<String> _paths = [];
  final _selected = <String>{};
  bool _loading = true;
  bool _confirming = false;
  bool _finished = false;
  late final OrganizerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(organizerProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  @override
  void dispose() {
    if (_loading) _controller.cancelMaintenance();
    super.dispose();
  }

  Future<void> _scan() async {
    if (!mounted) return;
    final paths = await _controller.scanEmptyDirectories();
    if (!mounted) return;
    setState(() {
      _paths = paths;
      _selected.addAll(paths);
      _loading = false;
    });
  }

  Future<void> _clean() async {
    setState(() => _loading = true);
    await _controller.cleanEmptyDirectories(_selected);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _finished = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final organizer = ref.watch(organizerProvider);
    return PopScope(
      canPop: !_loading,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 560,
            maxHeight: MediaQuery.sizeOf(context).height * .75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.cleanEmptyDirectories,
                style: context.theme.typography.body.lg,
              ),
              const SizedBox(height: 16),
              if (_loading) ...[
                Text(l.scanningOrCleaning),
                const SizedBox(height: 8),
                Text(
                  organizer.progress,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ] else if (_finished || organizer.message.isNotEmpty)
                Flexible(
                  child: SingleChildScrollView(
                    child: Text(localizeRuntimeMessage(l, organizer.message)),
                  ),
                )
              else if (_paths.isEmpty)
                Text(l.noEmptyDirectories)
              else ...[
                Text(l.emptyDirectoriesFound(_paths.length)),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _paths.length,
                    itemBuilder: (context, index) {
                      final path = _paths[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: FCheckbox(
                          value: _selected.contains(path),
                          enabled: !_confirming,
                          label: Text(displayDavPath(path)),
                          onChange: (value) => setState(() {
                            value
                                ? _selected.add(path)
                                : _selected.remove(path);
                          }),
                        ),
                      );
                    },
                  ),
                ),
                if (_confirming) ...[
                  const SizedBox(height: 12),
                  Text(l.emptyDirectoryDeleteWarning),
                ],
              ],
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 12,
                runSpacing: 8,
                children: [
                  if (_loading)
                    FButton(
                      variant: .outline,
                      onPress: _controller.cancelMaintenance,
                      child: Text(l.assistantStop),
                    )
                  else ...[
                    FButton(
                      variant: .outline,
                      onPress: () => Navigator.of(context).pop(),
                      child: Text(l.close),
                    ),
                    if (!_finished && _selected.isNotEmpty)
                      FButton(
                        onPress: _confirming
                            ? _clean
                            : () => setState(() => _confirming = true),
                        child: Text(
                          _confirming
                              ? l.confirmDeleteEmptyDirectories
                              : l.cleanSelectedDirectories(_selected.length),
                        ),
                      ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
