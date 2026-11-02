import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart' show SelectableText;

import '../../../shared/widgets.dart';
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
          loading: () => const Surface(child: Text('加载中…')),
          error: (e, _) => Surface(child: Text('读取记录失败：$e')),
          data: (items) {
            final entries = HistoryEntry.fromRecords(items);
            if (entries.isEmpty) {
              return const Surface(child: Text('暂无执行记录'));
            }
            final groups = <String, List<HistoryEntry>>{};
            for (final entry in entries) {
              groups.putIfAbsent(_date(entry.time), () => []).add(entry);
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${entries.length} 项操作',
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

String _date(DateTime? time) {
  if (time == null) return '其他记录';
  final local = time.toLocal();
  final today = DateTime.now();
  final date = DateTime(local.year, local.month, local.day);
  final now = DateTime(today.year, today.month, today.day);
  if (date == now) return '今天';
  if (date == DateTime(now.year, now.month, now.day - 1)) return '昨天';
  return '${local.year}-${_two(local.month)}-${_two(local.day)}';
}

String _two(int value) => value.toString().padLeft(2, '0');

String _clock(DateTime time) {
  final local = time.toLocal();
  return '${_two(local.hour)}:${_two(local.minute)}:${_two(local.second)}';
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
                child: Text(entry.title, style: theme.typography.body.md),
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
                      Text(entry.completed! ? '已完成' : '已发起'),
                    ],
                  ),
                ),
              const SizedBox(width: 8),
              FButton.icon(
                variant: .ghost,
                size: .sm,
                semanticsLabel: expanded ? '收起记录详情' : '展开记录详情',
                onPress: () => setState(() => expanded = !expanded),
                child: Icon(
                  expanded ? FLucideIcons.chevronUp : FLucideIcons.chevronDown,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (entry.source != null) ...[
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
          ] else
            Text(
              entry.message,
              style: muted,
              maxLines: expanded ? null : 2,
              overflow: expanded ? null : TextOverflow.ellipsis,
            ),
          if (entry.time != null) ...[
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
            if (entry.startedAt != null) ...[
              Text('开始于 ${_clock(entry.startedAt!)}', style: muted),
              const SizedBox(height: 8),
            ],
            SelectableText(entry.raw, style: muted),
          ],
        ],
      ),
    );
  }
}
