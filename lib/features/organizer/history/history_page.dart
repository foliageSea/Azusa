import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart' show SelectableText;

import '../../../shared/widgets.dart';
import '../../../shared/localization.dart';
import '../../../shared/status_badge.dart';
import 'history_entry.dart';
import '../organizer_state.dart';

class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(executionHistoryProvider);
    return PageContent(
      children: [
        history.when(
          loading: () => Surface(child: Text(context.l10n.loading)),
          error: (e, _) =>
              Surface(child: Text(context.l10n.historyLoadFailed('$e'))),
          data: (items) {
            final entries = HistoryEntry.fromRecords(items);
            if (entries.isEmpty) {
              return Surface(child: Text(context.l10n.noExecutionHistory));
            }
            final groups = <String, List<HistoryEntry>>{};
            for (final entry in entries) {
              groups
                  .putIfAbsent(_date(context, entry.time), () => [])
                  .add(entry);
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.l10n.operationCount(entries.length),
                  style: context.theme.typography.body.sm.copyWith(
                    color: context.theme.colors.mutedForeground,
                  ),
                ),
                for (final group in groups.entries) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 20, bottom: 10),
                    child: Text(
                      group.key,
                      style: context.theme.typography.body.md,
                    ),
                  ),
                  Surface(
                    padding: 0,
                    child: Column(
                      children: [
                        for (final (index, entry) in group.value.indexed) ...[
                          if (index > 0)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: SizedBox(
                                height: 1,
                                child: ColoredBox(
                                  color: context.theme.colors.border,
                                ),
                              ),
                            ),
                          _HistoryRow(entry: entry),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

String _date(BuildContext context, DateTime? time) {
  if (time == null) return context.l10n.otherRecords;
  final local = time.toLocal();
  final today = DateTime.now();
  final date = DateTime(local.year, local.month, local.day);
  final now = DateTime(today.year, today.month, today.day);
  if (date == now) return context.l10n.today;
  if (date == DateTime(now.year, now.month, now.day - 1)) {
    return context.l10n.yesterday;
  }
  return '${local.year}-${_two(local.month)}-${_two(local.day)}';
}

String _two(int value) => value.toString().padLeft(2, '0');

String _clock(DateTime time) {
  final local = time.toLocal();
  return '${_two(local.hour)}:${_two(local.minute)}:${_two(local.second)}';
}

String _dateTime(DateTime time) {
  final local = time.toLocal();
  return '${local.year}-${_two(local.month)}-${_two(local.day)} ${_clock(local)}';
}

String _fileName(String path) =>
    path.replaceFirst(RegExp(r'/+$'), '').split('/').last;

class _HistoryRow extends StatefulWidget {
  const _HistoryRow({required this.entry});
  final HistoryEntry entry;

  @override
  State<_HistoryRow> createState() => _HistoryRowState();
}

class _HistoryRowState extends State<_HistoryRow> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final theme = context.theme;
    final muted = theme.typography.body.sm.copyWith(
      color: theme.colors.mutedForeground,
    );
    final icon = switch (entry.action) {
      '重命名' || 'move' => FLucideIcons.folderPen,
      'upload' => FLucideIcons.upload,
      'delete' => FLucideIcons.trash2,
      'mkdir' => FLucideIcons.folderPlus,
      _ => FLucideIcons.history,
    };
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: theme.colors.mutedForeground),
              const SizedBox(width: 10),
              Expanded(
                child: Text(switch (entry.action) {
                  '重命名' => context.l10n.renameAction,
                  'move' => context.l10n.moveAction,
                  'upload' => context.l10n.uploadAction,
                  'delete' => context.l10n.delete,
                  'mkdir' => context.l10n.createDirectory,
                  _ => context.l10n.operationRecord,
                }, style: theme.typography.body.md),
              ),
              if (entry.completed != null)
                StatusBadge(
                  tone: entry.completed! ? StatusTone.success : StatusTone.info,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        entry.completed!
                            ? FLucideIcons.circleCheck
                            : FLucideIcons.clock,
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        entry.completed!
                            ? context.l10n.completed
                            : context.l10n.initiated,
                      ),
                    ],
                  ),
                ),
              const SizedBox(width: 8),
              FButton.icon(
                variant: .ghost,
                size: .sm,
                semanticsLabel: expanded
                    ? context.l10n.collapseHistory
                    : context.l10n.expandHistory,
                onPress: () => setState(() => expanded = !expanded),
                child: Icon(
                  expanded ? FLucideIcons.chevronUp : FLucideIcons.chevronDown,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (entry.source != null && !expanded) ...[
            Text(
              _fileName(entry.source!),
              style: entry.target == null ? theme.typography.body.sm : muted,
              maxLines: expanded ? null : 2,
              overflow: expanded ? null : TextOverflow.ellipsis,
            ),
            if (entry.target != null) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    FLucideIcons.cornerDownRight,
                    size: 16,
                    color: theme.colors.mutedForeground,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _fileName(entry.target!),
                      style: theme.typography.body.sm,
                      maxLines: expanded ? null : 2,
                      overflow: expanded ? null : TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ] else if (entry.source == null && !expanded)
            Text(
              entry.message,
              style: muted,
              maxLines: expanded ? null : 2,
              overflow: expanded ? null : TextOverflow.ellipsis,
            ),
          if (entry.time != null && !expanded) ...[
            const SizedBox(height: 10),
            Text(
              _clock(entry.time!),
              style: theme.typography.body.xs.copyWith(
                color: theme.colors.mutedForeground,
              ),
            ),
          ],
          if (expanded) ...[
            const SizedBox(height: 12),
            if (entry.time != null || entry.startedAt != null) ...[
              Wrap(
                spacing: 24,
                runSpacing: 8,
                children: [
                  if (entry.startedAt != null)
                    Text(
                      context.l10n.startedAtTime(_dateTime(entry.startedAt!)),
                      style: muted,
                    ),
                  if (entry.time != null)
                    Text(
                      entry.completed == true
                          ? context.l10n.completedAtTime(_dateTime(entry.time!))
                          : context.l10n.startedAtTime(_dateTime(entry.time!)),
                      style: muted,
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            if (entry.source != null) ...[
              _HistoryPath(
                label: context.l10n.originalPath,
                path: entry.source!,
              ),
              if (entry.target != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 6,
                    horizontal: 12,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Icon(
                      FLucideIcons.arrowDown,
                      size: 16,
                      color: theme.colors.mutedForeground,
                    ),
                  ),
                ),
                _HistoryPath(
                  label: context.l10n.newPath,
                  path: entry.target!,
                  target: true,
                ),
              ],
            ] else
              SelectableText(entry.message, style: muted),
          ],
        ],
      ),
    );
  }
}

class _HistoryPath extends StatelessWidget {
  const _HistoryPath({
    required this.label,
    required this.path,
    this.target = false,
  });
  final String label, path;
  final bool target;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colors.muted,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.typography.body.xs.copyWith(
              color: theme.colors.mutedForeground,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            path,
            style: theme.typography.body.sm.copyWith(
              color: target
                  ? theme.colors.foreground
                  : theme.colors.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}
