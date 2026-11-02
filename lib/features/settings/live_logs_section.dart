import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/logging/live_log_store.dart';
import '../../shared/localization.dart';
import '../../shared/responsive_button.dart';
import '../../shared/widgets.dart';
import 'live_log_controller.dart';
import 'live_log_text.dart';

class LiveLogsSection extends ConsumerStatefulWidget {
  const LiveLogsSection({this.fill = false, super.key});

  final bool fill;

  @override
  ConsumerState<LiveLogsSection> createState() => _LiveLogsSectionState();
}

class _LiveLogsSectionState extends ConsumerState<LiveLogsSection> {
  late final LiveLogController _logs;
  final _scroll = ScrollController();
  bool _following = true;
  bool _scrollScheduled = false;

  @override
  void initState() {
    super.initState();
    _logs = LiveLogController(ref.read(liveLogStoreProvider));
    _logs.addListener(_scheduleFollow);
    _scheduleFollow();
  }

  void _scheduleFollow() {
    if (!_following || _logs.paused || _scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (!mounted || !_following || _logs.paused || !_scroll.hasClients) {
        return;
      }
      final position = _scroll.position;
      if ((position.maxScrollExtent - position.pixels).abs() > 0.5) {
        _scroll.jumpTo(position.maxScrollExtent);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _copy(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        notifyUser(context, context.l10n.copied, type: NoticeType.success);
      }
    } catch (_) {
      if (mounted) {
        notifyUser(context, context.l10n.logCopyError, type: NoticeType.error);
      }
    }
  }

  @override
  void dispose() {
    _logs.removeListener(_scheduleFollow);
    _logs.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Widget _frame(
    BuildContext context, {
    required bool compact,
    required Widget child,
  }) {
    final box = Container(
      decoration: BoxDecoration(
        border: Border.all(color: context.theme.colors.border),
        borderRadius: context.theme.style.borderRadius.md,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
    if (widget.fill) return Expanded(child: box);
    return SizedBox(
      height: (MediaQuery.sizeOf(context).height * (compact ? 0.6 : 0.45))
          .clamp(compact ? 280 : 240, 600),
      child: box,
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _logs,
    builder: (context, _) {
      final l = context.l10n;
      final entries = _logs.entries;
      final indices = {
        for (var i = 0; i < entries.length; i++) 'live-log-${entries[i].id}': i,
      };
      final compact = MediaQuery.sizeOf(context).width < 480;
      final search = FTextField(
        key: const ValueKey('log-search'),
        hint: l.searchLogs,
        control: .managed(onChange: (value) => _logs.setQuery(value.text)),
      );
      final level = FSelect<Level>.rich(
        key: const ValueKey('log-level'),
        control: .lifted(
          value: _logs.minimumLevel,
          onChange: (value) => _logs.setMinimumLevel(value ?? Level.ALL),
        ),
        format: (value) => value == Level.ALL ? l.all : '${value.name}+',
        children: [
          FSelectItem(title: Text(l.all), value: Level.ALL),
          for (final value in [
            Level.FINE,
            Level.INFO,
            Level.WARNING,
            Level.SEVERE,
            Level.SHOUT,
          ])
            FSelectItem(title: Text('${value.name}+'), value: value),
        ],
      );
      final buttons = [
        FButton(
          key: const ValueKey('pause-logs'),
          builder: responsiveButtonContent,
          mainAxisSize: MainAxisSize.min,
          variant: .outline,
          onPress: _logs.togglePaused,
          prefix: Icon(_logs.paused ? FLucideIcons.play : FLucideIcons.pause),
          child: Text(_logs.paused ? l.resumeLogs : l.pauseLogs),
        ),
        FButton(
          key: const ValueKey('follow-logs'),
          builder: responsiveButtonContent,
          mainAxisSize: MainAxisSize.min,
          variant: _following ? .primary : .outline,
          selected: _following,
          onPress: () {
            setState(() => _following = !_following);
            _scheduleFollow();
          },
          child: Text(l.autoScrollLogs),
        ),
        if (compact) ...[
          FButton.icon(
            key: const ValueKey('copy-logs'),
            variant: .outline,
            semanticsLabel: l.copyVisibleLogs,
            onPress: entries.isEmpty ? null : () => _copy(_logs.copyText),
            child: const Icon(FLucideIcons.copy),
          ),
          FButton.icon(
            key: const ValueKey('clear-logs'),
            variant: .outline,
            semanticsLabel: l.clearLogView,
            onPress: _logs.clearView,
            child: const Icon(FLucideIcons.eraser),
          ),
        ] else ...[
          FButton(
            key: const ValueKey('copy-logs'),
            builder: responsiveButtonContent,
            mainAxisSize: MainAxisSize.min,
            variant: .outline,
            onPress: entries.isEmpty ? null : () => _copy(_logs.copyText),
            child: Text(l.copyVisibleLogs),
          ),
          FButton(
            key: const ValueKey('clear-logs'),
            builder: responsiveButtonContent,
            mainAxisSize: MainAxisSize.min,
            variant: .outline,
            onPress: _logs.clearView,
            child: Text(l.clearLogView),
          ),
        ],
      ];
      final count = Text(
        l.logEntryCount(entries.length),
        key: const ValueKey('log-entry-count'),
        textAlign: compact ? TextAlign.left : TextAlign.right,
        style: context.theme.typography.body.xs.copyWith(
          color: context.theme.colors.mutedForeground,
        ),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: compact ? 12 : 20),
          if (compact)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: search),
                const SizedBox(width: 8),
                SizedBox(width: 120, child: level),
              ],
            )
          else
            Row(
              children: [
                Expanded(child: search),
                const SizedBox(width: 12),
                SizedBox(width: 160, child: level),
              ],
            ),
          const SizedBox(height: 12),
          ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: buttons,
            ),
            const SizedBox(height: 8),
            count,
          ],
          const SizedBox(height: 8),
          _frame(
            context,
            compact: compact,
            child: entries.isEmpty
                ? Center(
                    child: Icon(
                      FLucideIcons.inbox,
                      key: const ValueKey('empty-logs-icon'),
                      size: 32,
                      color: context.theme.colors.mutedForeground,
                      semanticLabel: l.noLiveLogs,
                    ),
                  )
                : NotificationListener<ScrollMetricsNotification>(
                    onNotification: (notification) {
                      // Lazy variable-height rows refine their extent as they
                      // are laid out; resizing can change it as well.
                      if (notification.depth == 0) _scheduleFollow();
                      return false;
                    },
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification is ScrollUpdateNotification &&
                            notification.dragDetails != null &&
                            _following) {
                          setState(() => _following = false);
                        } else if (notification is UserScrollNotification &&
                            notification.direction != ScrollDirection.idle &&
                            _following) {
                          setState(() => _following = false);
                        }
                        return false;
                      },
                      child: ListView.builder(
                        key: const ValueKey('live-log-list'),
                        controller: _scroll,
                        padding: EdgeInsets.zero,
                        itemCount: entries.length,
                        findChildIndexCallback: (key) =>
                            key is ValueKey<String> ? indices[key.value] : null,
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          final decoration = BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: context.theme.colors.border,
                              ),
                            ),
                          );
                          if (compact) {
                            return GestureDetector(
                              key: ValueKey('live-log-${entry.id}'),
                              behavior: HitTestBehavior.opaque,
                              onLongPress: () {
                                HapticFeedback.selectionClick();
                                _copy(entry.text);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: decoration,
                                child: LiveLogText(entry: entry, compact: true),
                              ),
                            );
                          }
                          return Container(
                            key: ValueKey('live-log-${entry.id}'),
                            padding: const EdgeInsets.all(12),
                            decoration: decoration,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(child: LiveLogText(entry: entry)),
                                FButton.icon(
                                  key: ValueKey('copy-log-${entry.id}'),
                                  variant: .ghost,
                                  size: .xs,
                                  semanticsLabel: l.copyLogEntry,
                                  onPress: () => _copy(entry.text),
                                  child: const Icon(
                                    FLucideIcons.copy,
                                    size: 16,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
          ),
        ],
      );
    },
  );
}
