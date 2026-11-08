import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../shared/localization.dart';
import '../../../shared/runtime_localization.dart';
import '../dav/dav_paths.dart';
import '../organizer_state.dart';
import 'media_identity.dart';
import 'scrape_cleaner.dart';
import 'scraper.dart';

Future<void> showScrapeDialog(BuildContext context) => showFDialog<void>(
  context: context,
  builder: (context, style, animation) => FDialog(
    animation: animation,
    builder: (context, style) => const _ScrapeDialog(),
  ),
);

Future<void> showScrapeCleanupDialog(BuildContext context) => showFDialog<void>(
  context: context,
  builder: (context, style, animation) => FDialog(
    animation: animation,
    builder: (context, style) => const _ScrapeCleanupDialog(),
  ),
);

/// Toolbar menu offering metadata scraping and scraped-file cleanup.
class ScrapeButton extends ConsumerWidget {
  const ScrapeButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(organizerProvider);
    final locked = state.busy || state.executing || state.directory.isEmpty;
    final l = context.l10n;
    return FPopoverMenu(
      menuAnchor: Alignment.topRight,
      childAnchor: Alignment.bottomRight,
      menuBuilder: (_, controller, _) => [
        FItemGroup(children: scrapeMenuItems(context, controller, locked)),
      ],
      builder: (_, controller, _) => FButton(
        key: const ValueKey('scrape-menu'),
        variant: .outline,
        size: .sm,
        mainAxisSize: MainAxisSize.min,
        prefix: const Icon(FLucideIcons.scanSearch),
        onPress: locked ? null : controller.toggle,
        child: Text(l.scrapeMenu),
      ),
    );
  }
}

/// Menu items shared by the desktop scrape menu and the mobile action menu.
List<FItem> scrapeMenuItems(
  BuildContext context,
  FPopoverController controller,
  bool locked,
) {
  final l = context.l10n;
  Future<void> Function()? open(Future<void> Function(BuildContext) show) =>
      locked
      ? null
      : () async {
          await controller.hide();
          if (context.mounted) await show(context);
        };
  return [
    FItem(
      key: const ValueKey('scrape-metadata'),
      prefix: const Icon(FLucideIcons.scanSearch),
      title: Text(l.scrapeMetadata),
      onPress: open(showScrapeDialog),
    ),
    FItem(
      key: const ValueKey('scrape-cleanup'),
      prefix: const Icon(FLucideIcons.eraser),
      title: Text(l.cleanScrapedFiles),
      onPress: open(showScrapeCleanupDialog),
    ),
  ];
}

class _DialogFrame extends StatelessWidget {
  const _DialogFrame({
    required this.title,
    required this.busy,
    required this.body,
    required this.actions,
  });
  final String title;
  final bool busy;
  final List<Widget> body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 640,
          maxHeight: MediaQuery.sizeOf(context).height * .8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: context.theme.typography.body.lg),
            const SizedBox(height: 16),
            ...body,
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 12,
              runSpacing: 8,
              children: actions,
            ),
          ],
        ),
      ),
    ),
  );
}

class _ScrapeDialog extends ConsumerStatefulWidget {
  const _ScrapeDialog();

  @override
  ConsumerState<_ScrapeDialog> createState() => _ScrapeDialogState();
}

class _ScrapeDialogState extends ConsumerState<_ScrapeDialog> {
  ScrapeScan? _scan;
  final _selected = <String>{};
  bool _artwork = true;
  bool _loading = true;
  bool _writing = false;
  bool _finished = false;
  late final OrganizerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(organizerProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    if (_loading) _controller.cancelMaintenance();
    super.dispose();
  }

  Future<void> _start() async {
    if (!mounted) return;
    final scan = await _controller.scanScrapeTargets();
    if (!mounted) return;
    setState(() {
      _scan = scan;
      _selected.addAll([...?scan?.targets.map((t) => t.video)]);
      _loading = false;
    });
  }

  Future<void> _write() async {
    setState(() {
      _loading = true;
      _writing = true;
    });
    await _controller.executeScrape(_selected, artwork: _artwork);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _finished = true;
    });
  }

  String _describe(BuildContext context, ScrapeTarget target) {
    final l = context.l10n;
    final year = target.year == null ? '' : ' (${target.year})';
    if (target.kind == ScrapeMediaKind.movie) {
      return '${l.scrapeKindMovie} · ${target.title}$year';
    }
    final season = target.season.toString().padLeft(2, '0');
    final episode = target.episode.toString().padLeft(2, '0');
    return '${l.scrapeKindEpisode} · ${target.title}$year · S${season}E$episode';
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final organizer = ref.watch(organizerProvider);
    final scan = _scan;
    final targets = scan?.targets ?? const <ScrapeTarget>[];
    final muted = context.theme.typography.body.sm.copyWith(
      color: context.theme.colors.mutedForeground,
    );
    return _DialogFrame(
      title: l.scrapeMetadata,
      busy: _loading,
      body: [
        if (_loading) ...[
          Text(_writing ? l.scrapeWriting : l.scrapeScanning),
          const SizedBox(height: 8),
          Text(
            organizer.progress,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ] else if (_finished || organizer.message.isNotEmpty || scan == null)
          Flexible(
            child: SingleChildScrollView(
              child: Text(localizeRuntimeMessage(l, organizer.message)),
            ),
          )
        else if (targets.isEmpty && scan.unmatched.isEmpty)
          Text(l.scrapeNoVideos)
        else ...[
          Text(l.scrapeDetail, style: muted),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: Text(l.scrapeMatched(targets.length))),
              if (targets.isNotEmpty)
                FButton(
                  variant: .ghost,
                  size: .sm,
                  mainAxisSize: MainAxisSize.min,
                  onPress: () => setState(() {
                    _selected.length == targets.length
                        ? _selected.clear()
                        : _selected.addAll(targets.map((t) => t.video));
                  }),
                  child: Text(
                    _selected.length == targets.length
                        ? l.deselectAll
                        : l.selectAll,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final target in targets)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: FCheckbox(
                      value: _selected.contains(target.video),
                      label: Text(displayDavPath(target.video)),
                      description: Text(_describe(context, target)),
                      onChange: (value) => setState(() {
                        value
                            ? _selected.add(target.video)
                            : _selected.remove(target.video);
                      }),
                    ),
                  ),
                if (scan.unmatched.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(l.scrapeUnmatched(scan.unmatched.length)),
                  const SizedBox(height: 4),
                  for (final path in scan.unmatched.take(100))
                    Text(displayDavPath(path), style: muted),
                ],
              ],
            ),
          ),
          if (targets.isNotEmpty) ...[
            const SizedBox(height: 12),
            FCheckbox(
              key: const ValueKey('scrape-artwork'),
              value: _artwork,
              label: Text(l.scrapeIncludeArtwork),
              onChange: (value) => setState(() => _artwork = value),
            ),
          ],
        ],
      ],
      actions: [
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
          if (!_finished && scan != null && _selected.isNotEmpty)
            FButton(
              key: const ValueKey('scrape-execute'),
              onPress: _write,
              child: Text(l.scrapeSelected(_selected.length)),
            ),
        ],
      ],
    );
  }
}

class _ScrapeCleanupDialog extends ConsumerStatefulWidget {
  const _ScrapeCleanupDialog();

  @override
  ConsumerState<_ScrapeCleanupDialog> createState() =>
      _ScrapeCleanupDialogState();
}

class _ScrapeCleanupDialogState extends ConsumerState<_ScrapeCleanupDialog> {
  List<ScrapeArtifact> _artifacts = [];
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
    final artifacts = await _controller.scanScrapeArtifacts();
    if (!mounted) return;
    setState(() {
      _artifacts = artifacts;
      _selected.addAll(artifacts.map((a) => a.path));
      _loading = false;
    });
  }

  Future<void> _clean() async {
    setState(() => _loading = true);
    await _controller.cleanScrapeArtifacts(_selected);
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
    return _DialogFrame(
      title: l.cleanScrapedFiles,
      busy: _loading,
      body: [
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
        else if (_artifacts.isEmpty)
          Text(l.noScrapeArtifacts)
        else ...[
          Row(
            children: [
              Expanded(child: Text(l.scrapeArtifactsFound(_artifacts.length))),
              FButton(
                variant: .ghost,
                size: .sm,
                mainAxisSize: MainAxisSize.min,
                onPress: _confirming
                    ? null
                    : () => setState(() {
                        _selected.length == _artifacts.length
                            ? _selected.clear()
                            : _selected.addAll(_artifacts.map((a) => a.path));
                      }),
                child: Text(
                  _selected.length == _artifacts.length
                      ? l.deselectAll
                      : l.selectAll,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _artifacts.length,
              itemBuilder: (context, index) {
                final artifact = _artifacts[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: FCheckbox(
                    value: _selected.contains(artifact.path),
                    enabled: !_confirming,
                    label: Text(displayDavPath(artifact.path)),
                    description: Text(
                      artifact.kind == ScrapeArtifactKind.nfo
                          ? l.scrapeArtifactNfo
                          : l.scrapeArtifactImage,
                    ),
                    onChange: (value) => setState(() {
                      value
                          ? _selected.add(artifact.path)
                          : _selected.remove(artifact.path);
                    }),
                  ),
                );
              },
            ),
          ),
          if (_confirming) ...[
            const SizedBox(height: 12),
            Text(l.scrapeCleanupWarning),
          ],
        ],
      ],
      actions: [
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
              key: const ValueKey('scrape-cleanup-confirm'),
              onPress: _confirming
                  ? _clean
                  : () => setState(() => _confirming = true),
              child: Text(
                _confirming
                    ? l.confirmDeleteScrapeFiles
                    : l.cleanSelectedScrapeFiles(_selected.length),
              ),
            ),
        ],
      ],
    );
  }
}
