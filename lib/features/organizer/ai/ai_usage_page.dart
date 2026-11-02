import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import '../../../shared/widgets.dart';
import '../../../shared/localization.dart';
import '../../../shared/status_badge.dart';
import 'ai_usage_history.dart';
import '../dav/dav_paths.dart';

class AiUsagePage extends ConsumerWidget {
  const AiUsagePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(aiUsageHistoryProvider);
    return PageContent(
      children: [
        history.when(
          loading: () => const LoadingNotice(),
          error: (_, _) => Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.usageLoadFailed),
                const SizedBox(height: 12),
                FButton(
                  variant: .outline,
                  mainAxisSize: MainAxisSize.min,
                  onPress: () => ref.invalidate(aiUsageHistoryProvider),
                  child: Text(context.l10n.retry),
                ),
              ],
            ),
          ),
          data: (records) {
            final summary = AiUsageSummary(records);
            final sorted = [...records]
              ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
            final partial = summary.missingUsage > 0 ? '≥ ' : '';
            final cost = summary.analyses == 0
                ? '\$0.000000'
                : summary.pricedAnalyses == 0
                ? '—'
                : '${summary.pricedAnalyses < summary.analyses ? '≥ ' : ''}${_money(summary.estimatedCost)}';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MetricsGrid(
                  children: [
                    _Metric(context.l10n.analysisCount, '${summary.analyses}'),
                    _Metric(context.l10n.modelRequests, '${summary.responses}'),
                    _Metric(
                      context.l10n.totalInputTokens,
                      '$partial${summary.inputTokens}',
                    ),
                    _Metric(
                      context.l10n.totalOutputTokens,
                      '$partial${summary.outputTokens}',
                    ),
                    _Metric(
                      context.l10n.averageTps,
                      summary.tokensPerSecond?.toStringAsFixed(1) ?? '—',
                    ),
                    _Metric(context.l10n.totalEstimatedCost, cost),
                  ],
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    Text(
                      context.l10n.analysisHistory,
                      style: context.theme.typography.body.lg,
                    ),
                    if (summary.missingUsage > 0)
                      StatusBadge(
                        tone: StatusTone.warning,
                        child: Text(
                          context.l10n.incompleteUsageCount(
                            summary.missingUsage,
                          ),
                        ),
                      ),
                    if (summary.pricedAnalyses < summary.analyses)
                      StatusBadge(
                        tone: StatusTone.warning,
                        child: Text(
                          context.l10n.unknownCostCount(
                            summary.analyses - summary.pricedAnalyses,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (sorted.isEmpty)
                  Surface(child: Text(context.l10n.noAiUsage))
                else
                  for (final record in sorted) ...[
                    _RecordCard(record),
                    const SizedBox(height: 12),
                  ],
              ],
            );
          },
        ),
      ],
    );
  }
}

String _money(double value) => '\$${value.toStringAsFixed(6)}';

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) => Surface(
    padding: isMobileLayout(context) ? 12 : 20,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: context.theme.typography.body.sm.copyWith(
            color: context.theme.colors.mutedForeground,
          ),
        ),
        SizedBox(height: isMobileLayout(context) ? 4 : 8),
        Text(value, style: context.theme.typography.body.lg),
      ],
    ),
  );
}

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (!isMobileLayout(context)) {
      return AdaptiveGrid(minWidth: 200, children: children);
    }
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 8.0;
        final columns = box.maxWidth >= 260 ? 2 : 1;
        final width = (box.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard(this.record);
  final AiUsageRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final usage = record.usage;
    final partial = usage.missingUsage ? '≥ ' : '';
    return Surface(
      padding: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(record.model, style: theme.typography.body.md),
              ),
              const SizedBox(width: 12),
              StatusBadge(
                tone: record.succeeded ? StatusTone.success : StatusTone.error,
                child: Text(
                  record.succeeded
                      ? context.l10n.completed
                      : context.l10n.failed,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            displayDavPath(record.directory),
            style: theme.typography.body.sm,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 20,
            runSpacing: 8,
            children: [
              Text(context.l10n.usageInput('$partial${usage.inputTokens}')),
              Text(context.l10n.usageOutput('$partial${usage.outputTokens}')),
              Text('${usage.tokensPerSecond?.toStringAsFixed(1) ?? '—'} TPS'),
              Text(
                record.estimatedCost == null
                    ? context.l10n.unknownCost
                    : _money(record.estimatedCost!),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              Text(
                DateFormat('yyyy-MM-dd HH:mm:ss')
                    .format(record.startedAt.toLocal()),
                style: theme.typography.body.xs.copyWith(
                  color: theme.colors.mutedForeground,
                ),
              ),
              Text(
                context.l10n.modelRequestCount(usage.responses),
                style: theme.typography.body.xs.copyWith(
                  color: theme.colors.mutedForeground,
                ),
              ),
              if (record.priceSource != null)
                Text(
                  'models.dev · ${record.priceSource}',
                  style: theme.typography.body.xs.copyWith(
                    color: theme.colors.mutedForeground,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
