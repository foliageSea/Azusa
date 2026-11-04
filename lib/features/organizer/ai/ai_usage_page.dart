import 'dart:math' as math;

import 'package:flutter/material.dart' show Tooltip;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import '../../../shared/localization.dart';
import '../../../shared/status_badge.dart';
import '../../../shared/widgets.dart';
import '../dav/dav_paths.dart';
import 'ai_usage_history.dart';
import 'ai_usage_statistics.dart';

class AiUsagePage extends ConsumerStatefulWidget {
  const AiUsagePage({super.key});

  @override
  ConsumerState<AiUsagePage> createState() => _AiUsagePageState();
}

class _AiUsagePageState extends ConsumerState<AiUsagePage> {
  UsagePeriod _period = UsagePeriod.all;
  UsageStatus _status = UsageStatus.all;
  UsageSort _sort = UsageSort.newest;
  String? _model;
  String _query = '';
  int _limit = 20;

  void _filter(VoidCallback change) => setState(() {
    change();
    _limit = 20;
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return PageContent(
      children: [
        ref
            .watch(aiUsageHistoryProvider)
            .when(
              loading: () => const LoadingNotice(),
              error: (_, _) => EmptyNotice(
                l.usageLoadFailed,
                child: FButton(
                  mainAxisSize: MainAxisSize.min,
                  onPress: () => ref.invalidate(aiUsageHistoryProvider),
                  child: Text(l.retry),
                ),
              ),
              data: (records) {
                final now = DateTime.now();
                final models = records.map((r) => r.model).toSet().toList()
                  ..sort();
                final model = models.contains(_model) ? _model : null;
                final filtered = filterUsage(
                  records,
                  period: _period,
                  status: _status,
                  model: model,
                  now: now,
                );
                final summary = AiUsageSummary(filtered);
                final history = sortUsage(filtered, query: _query, sort: _sort);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final period in UsagePeriod.values)
                          FButton(
                            variant: _period == period ? .primary : .outline,
                            mainAxisSize: MainAxisSize.min,
                            onPress: () => _filter(() => _period = period),
                            child: Text(switch (period) {
                              UsagePeriod.today => l.today,
                              UsagePeriod.week => l.usageWeek,
                              UsagePeriod.month => l.usageMonth,
                              UsagePeriod.all => l.all,
                            }),
                          ),
                        _Choice<String>(
                          key: const ValueKey('usage-model-filter'),
                          value: model ?? '',
                          values: {
                            '': '${l.modelName} · ${l.all}',
                            for (final m in models) m: m,
                          },
                          onChange: (value) => _filter(
                            () => _model = value.isEmpty ? null : value,
                          ),
                        ),
                        _Choice<UsageStatus>(
                          value: _status,
                          values: {
                            UsageStatus.all: '${l.usageStatus} · ${l.all}',
                            UsageStatus.succeeded: l.completed,
                            UsageStatus.failed: l.failed,
                          },
                          onChange: (value) => _filter(() => _status = value),
                        ),
                        FButton(
                          variant: .outline,
                          mainAxisSize: MainAxisSize.min,
                          onPress: () => ref.invalidate(aiUsageHistoryProvider),
                          child: Text(l.usageRefresh),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _MetricsGrid(
                      children: [
                        _Metric(
                          l.totalEstimatedCost,
                          _cost(summary),
                          '${l.usageAverageCost}  ${summary.averageCost == null ? '—' : _money(summary.averageCost!)}',
                        ),
                        _Metric(
                          l.analysisCount,
                          _number(summary.analyses),
                          '${l.completed} ${_number(summary.succeeded)}  ·  ${l.failed} ${_number(summary.failed)}',
                        ),
                        _Metric(
                          l.modelRequests,
                          _number(summary.responses),
                          '${l.usageRequestsPerAnalysis}  ${summary.requestsPerAnalysis?.toStringAsFixed(1) ?? '—'}',
                        ),
                        _Metric(
                          l.totalInputTokens,
                          _tokens(summary.inputTokens, summary),
                          '${l.usageCachedTokens}  ${_tokens(summary.cachedTokens, summary)}',
                        ),
                        _Metric(
                          l.totalOutputTokens,
                          _tokens(summary.outputTokens, summary),
                          '${l.usageCacheRate}  ${_percent(summary.cacheHitRate)}',
                        ),
                        _Metric(
                          l.usageModelPerformance,
                          '${summary.tokensPerSecond?.toStringAsFixed(1) ?? '—'} TPS',
                          '${l.usageAverageRequestTime}  ${_duration(summary.averageRequestTime)}',
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _Completeness(summary),
                    if (filtered.isNotEmpty) ...[
                      _Trend(
                        days: usageByDay(filtered, period: _period, now: now),
                      ),
                      const SizedBox(height: 20),
                      _ModelTable(groups: usageByModel(filtered)),
                      const SizedBox(height: 24),
                    ],
                    Text(
                      l.analysisHistory,
                      style: context.theme.typography.body.lg,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        SizedBox(
                          width: isMobileLayout(context)
                              ? double.infinity
                              : 320,
                          child: FTextField(
                            hint: l.usageDirectorySearch,
                            control: .managed(
                              onChange: (value) =>
                                  _filter(() => _query = value.text),
                            ),
                          ),
                        ),
                        _Choice<UsageSort>(
                          value: _sort,
                          values: {
                            UsageSort.newest: l.usageNewest,
                            UsageSort.cost: l.usageHighestCost,
                          },
                          onChange: (value) => _filter(() => _sort = value),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (history.isEmpty)
                      EmptyNotice(
                        records.isEmpty ? l.noAiUsage : l.usageNoMatches,
                      )
                    else ...[
                      if (!isMobileLayout(context)) _RecordHeader(),
                      for (final record in history.take(_limit)) ...[
                        _RecordCard(record, key: ObjectKey(record)),
                        const SizedBox(height: 8),
                      ],
                      if (history.length > _limit)
                        FButton(
                          variant: .outline,
                          onPress: () => setState(() => _limit += 20),
                          child: Text(
                            '${l.usageLoadMore} (${math.min(_limit, history.length)} / ${history.length})',
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

String _number(int value) => NumberFormat.decimalPattern().format(value);
String _money(double value) => '\$${value.toStringAsFixed(6)}';
String _percent(double? value) =>
    value == null ? '—' : '${(value * 100).toStringAsFixed(1)}%';
String _duration(Duration? value) => value == null
    ? '—'
    : '${(value.inMicroseconds / 1000000).toStringAsFixed(2)} s';
String _tokens(int value, AiUsageSummary summary) =>
    '${summary.missingUsage > 0 ? '≥ ' : ''}${_number(value)}';
String _cost(AiUsageSummary summary) => summary.analyses == 0
    ? _money(0)
    : summary.pricedAnalyses == 0
    ? '—'
    : '${summary.pricedAnalyses < summary.analyses ? '≥ ' : ''}${_money(summary.estimatedCost)}';

class _Choice<T> extends StatelessWidget {
  const _Choice({
    required this.value,
    required this.values,
    required this.onChange,
    super.key,
  });
  final T value;
  final Map<T, String> values;
  final ValueChanged<T> onChange;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: isMobileLayout(context) ? 160 : 190,
    child: FSelect<T>.rich(
      format: (value) => values[value] ?? '',
      control: .lifted(
        value: value,
        onChange: (value) {
          if (value != null) onChange(value);
        },
      ),
      children: [
        for (final entry in values.entries)
          FSelectItem(title: Text(entry.value), value: entry.key),
      ],
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.detail);
  final String label, value, detail;

  @override
  Widget build(BuildContext context) => Surface(
    padding: isMobileLayout(context) ? 12 : 20,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Muted(label),
        const SizedBox(height: 8),
        Text(value, style: context.theme.typography.body.xl),
        const SizedBox(height: 8),
        _Muted(detail),
      ],
    ),
  );
}

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final columns = box.maxWidth >= 760
          ? 3
          : box.maxWidth >= 300
          ? 2
          : 1;
      final gap = isMobileLayout(context) ? 8.0 : 16.0;
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

class _Muted extends StatelessWidget {
  const _Muted(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: context.theme.typography.body.sm.copyWith(
      color: context.theme.colors.mutedForeground,
    ),
  );
}

class _Completeness extends StatelessWidget {
  const _Completeness(this.summary);
  final AiUsageSummary summary;
  @override
  Widget build(BuildContext context) {
    if (summary.missingUsage == 0 &&
        summary.pricedAnalyses == summary.analyses) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (summary.missingUsage > 0)
            StatusBadge(
              tone: StatusTone.warning,
              child: Text(
                context.l10n.incompleteUsageCount(summary.missingUsage),
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
    );
  }
}

enum _TrendMetric { cost, tokens, requests }

class _Trend extends StatefulWidget {
  const _Trend({required this.days});
  final List<UsageDayGroup> days;
  @override
  State<_Trend> createState() => _TrendState();
}

class _TrendState extends State<_Trend> {
  _TrendMetric _metric = _TrendMetric.cost;
  DateTime? _selected;

  double _value(AiUsageSummary s) => switch (_metric) {
    _TrendMetric.cost => s.estimatedCost,
    _TrendMetric.tokens => (s.inputTokens + s.outputTokens).toDouble(),
    _TrendMetric.requests => s.responses.toDouble(),
  };

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final days = widget.days;
    final selected =
        days.where((d) => d.day == _selected).firstOrNull ?? days.last;
    final maxValue = days.fold<double>(
      0,
      (max, day) => math.max(max, _value(day.summary)),
    );
    final inputColor = context.theme.colors.primary;
    const outputColor = Color(0xFF38A89D);
    String detail(AiUsageSummary s) => switch (_metric) {
      _TrendMetric.cost => '${l.estimatedCost} ${_cost(s)}',
      _TrendMetric.tokens =>
        '${l.usageInput(_tokens(s.inputTokens, s))}  ·  ${l.usageOutput(_tokens(s.outputTokens, s))}',
      _TrendMetric.requests => '${l.modelRequests} ${_number(s.responses)}',
    };
    return Surface(
      padding: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(l.usageTrend, style: context.theme.typography.body.lg),
              _Choice<_TrendMetric>(
                key: const ValueKey('usage-trend-metric'),
                value: _metric,
                values: {
                  _TrendMetric.cost: l.estimatedCost,
                  _TrendMetric.tokens: l.usageTokens,
                  _TrendMetric.requests: l.modelRequests,
                },
                onChange: (value) => setState(() => _metric = value),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${DateFormat.yMMMd().format(selected.day)}  ·  ${detail(selected.summary)}',
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 158,
            child: LayoutBuilder(
              builder: (context, box) {
                final width = math.max(
                  38.0,
                  box.maxWidth / math.min(days.length, 30),
                );
                return ListView.builder(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  itemCount: days.length,
                  itemBuilder: (context, index) {
                    final day = days[days.length - index - 1];
                    final s = day.summary;
                    final value = _value(s);
                    final height = maxValue == 0 ? 0.0 : 112 * value / maxValue;
                    final outputRatio = s.inputTokens + s.outputTokens == 0
                        ? 0.0
                        : s.outputTokens / (s.inputTokens + s.outputTokens);
                    return SizedBox(
                      width: width,
                      child: Tooltip(
                        message:
                            '${DateFormat.yMMMd().format(day.day)}\n${detail(s)}',
                        child: GestureDetector(
                          onTap: () => setState(() => _selected = day.day),
                          child: Semantics(
                            button: true,
                            selected: day.day == selected.day,
                            label:
                                '${DateFormat.yMMMd().format(day.day)} ${detail(s)}',
                            child: Column(
                              children: [
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.bottomCenter,
                                    child: Container(
                                      width: math.min(width - 12, 28),
                                      height: math.max(height, 2),
                                      decoration: BoxDecoration(
                                        border: day.day == selected.day
                                            ? Border.all(
                                                color: outputColor,
                                                width: 2,
                                              )
                                            : null,
                                        color: context.theme.colors.muted,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: value == 0
                                          ? null
                                          : Column(
                                              children: [
                                                if (_metric ==
                                                        _TrendMetric.tokens &&
                                                    outputRatio > 0)
                                                  Expanded(
                                                    flex: math.max(
                                                      1,
                                                      (outputRatio * 1000)
                                                          .round(),
                                                    ),
                                                    child: const ColoredBox(
                                                      color: outputColor,
                                                      child: SizedBox.expand(),
                                                    ),
                                                  ),
                                                if (_metric !=
                                                        _TrendMetric.tokens ||
                                                    outputRatio < 1)
                                                  Expanded(
                                                    flex:
                                                        _metric ==
                                                            _TrendMetric.tokens
                                                        ? math.max(
                                                            1,
                                                            ((1 - outputRatio) *
                                                                    1000)
                                                                .round(),
                                                          )
                                                        : 1,
                                                    child: ColoredBox(
                                                      color: inputColor,
                                                      child:
                                                          const SizedBox.expand(),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  DateFormat('MM/dd').format(day.day),
                                  style: context.theme.typography.body.xs,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (_metric == _TrendMetric.tokens) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              children: [
                _Legend(l.inputTokens, inputColor),
                _Legend(l.outputTokens, outputColor),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.label, this.color);
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 6),
      _Muted(label),
    ],
  );
}

class _ModelTable extends StatelessWidget {
  const _ModelTable({required this.groups});
  final List<UsageModelGroup> groups;
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Surface(
      padding: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.usageModels, style: context.theme.typography.body.lg),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              columnWidths: const {
                0: FixedColumnWidth(200),
                1: FixedColumnWidth(90),
                2: FixedColumnWidth(90),
                3: FixedColumnWidth(170),
                4: FixedColumnWidth(110),
                5: FixedColumnWidth(90),
                6: FixedColumnWidth(130),
              },
              children: [
                TableRow(
                  children: [
                    for (final label in [
                      l.modelName,
                      l.analysisCount,
                      l.modelRequests,
                      '${l.inputTokens} / ${l.outputTokens}',
                      l.usageCacheRate,
                      l.averageTps,
                      l.estimatedCost,
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12, right: 12),
                        child: _Muted(label),
                      ),
                  ],
                ),
                for (final group in groups)
                  TableRow(
                    children: [
                      for (final value in [
                        group.model,
                        _number(group.summary.analyses),
                        _number(group.summary.responses),
                        '${_tokens(group.summary.inputTokens, group.summary)} / ${_tokens(group.summary.outputTokens, group.summary)}',
                        _percent(group.summary.cacheHitRate),
                        group.summary.tokensPerSecond?.toStringAsFixed(1) ??
                            '—',
                        _cost(group.summary),
                      ])
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10)
                              .copyWith(right: 12),
                          child: Text(value),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: _Muted('${l.usageTime} / ${l.modelName} / ${l.folder}'),
          ),
          Expanded(
            flex: 2,
            child: _Muted('${l.inputTokens} / ${l.outputTokens}'),
          ),
          Expanded(child: _Muted(l.usageModelTime)),
          Expanded(child: _Muted(l.estimatedCost)),
          const SizedBox(width: 120),
        ],
      ),
    );
  }
}

class _RecordCard extends StatefulWidget {
  const _RecordCard(this.record, {super.key});
  final AiUsageRecord record;
  @override
  State<_RecordCard> createState() => _RecordCardState();
}

class _RecordCardState extends State<_RecordCard> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final usage = record.usage;
    final summary = AiUsageSummary([record]);
    final l = context.l10n;
    final mobile = isMobileLayout(context);
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(record.model),
        const SizedBox(height: 4),
        _Muted(
          DateFormat('yyyy-MM-dd HH:mm:ss').format(record.startedAt.toLocal()),
        ),
        const SizedBox(height: 4),
        Text(
          displayDavPath(record.directory),
          maxLines: _expanded ? null : 1,
          overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          style: context.theme.typography.body.sm,
        ),
      ],
    );
    final badge = StatusBadge(
      tone: record.succeeded ? StatusTone.success : StatusTone.error,
      child: Text(record.succeeded ? l.completed : l.failed),
    );
    final toggle = FButton(
      variant: .ghost,
      mainAxisSize: MainAxisSize.min,
      onPress: () => setState(() => _expanded = !_expanded),
      child: Icon(
        _expanded ? FLucideIcons.chevronUp : FLucideIcons.chevronDown,
        size: 16,
        semanticLabel: _expanded ? l.collapseHistory : l.expandHistory,
      ),
    );
    return Surface(
      padding: mobile ? 12 : 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (mobile) ...[
            Row(
              children: [
                Expanded(child: identity),
                const SizedBox(width: 8),
                badge,
                toggle,
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                Text(l.usageInput(_tokens(usage.inputTokens, summary))),
                Text(l.usageOutput(_tokens(usage.outputTokens, summary))),
                Text(_duration(usage.responses == 0 ? null : usage.modelTime)),
                Text(_cost(summary)),
              ],
            ),
          ] else
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: identity,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    '${_tokens(usage.inputTokens, summary)} / ${_tokens(usage.outputTokens, summary)}',
                  ),
                ),
                Expanded(
                  child: Text(
                    _duration(usage.responses == 0 ? null : usage.modelTime),
                  ),
                ),
                Expanded(child: Text(_cost(summary))),
                SizedBox(
                  width: 120,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [badge, toggle],
                  ),
                ),
              ],
            ),
          if (_expanded) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                _Muted(
                  '${l.usageCachedTokens}  ${_tokens(usage.cachedTokens, summary)}',
                ),
                _Muted(
                  '${l.usageCacheRate}  ${_percent(summary.cacheHitRate)}',
                ),
                _Muted(l.modelRequestCount(usage.responses)),
                _Muted(
                  '${l.usageModelTime}  ${_duration(usage.responses == 0 ? null : usage.modelTime)}',
                ),
                _Muted(
                  '${l.usageAverageRequestTime}  ${_duration(summary.averageRequestTime)}',
                ),
                _Muted(
                  '${l.averageTps}  ${usage.tokensPerSecond?.toStringAsFixed(1) ?? '—'}',
                ),
              ],
            ),
            if (record.priceSource != null) ...[
              const SizedBox(height: 12),
              _Muted(
                '${l.usagePriceSource}  models.dev · ${record.priceSource}',
              ),
            ],
            const SizedBox(height: 12),
            _Completeness(summary),
          ],
        ],
      ),
    );
  }
}
