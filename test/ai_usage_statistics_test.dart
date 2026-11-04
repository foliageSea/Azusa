import 'package:azusa/features/organizer/ai/ai_usage.dart';
import 'package:azusa/features/organizer/ai/ai_usage_history.dart';
import 'package:azusa/features/organizer/ai/ai_usage_statistics.dart';
import 'package:flutter_test/flutter_test.dart';

AiUsageRecord record({
  required DateTime time,
  String model = 'model-a',
  bool succeeded = true,
  bool missing = false,
  double? cost = .01,
  String directory = '/dav/Series/',
}) => AiUsageRecord(
  startedAt: time,
  model: model,
  directory: directory,
  succeeded: succeeded,
  estimatedCost: cost,
  usage: AiUsage(
    inputTokens: 1000,
    cachedTokens: 250,
    outputTokens: 100,
    responses: 2,
    modelTime: const Duration(seconds: 4),
    missingUsage: missing,
  ),
);

void main() {
  final now = DateTime(2026, 11, 4, 12);

  test('汇总成功率、缓存、均价和请求耗时；缓存不重复计入输入', () {
    final summary = AiUsageSummary([
      record(time: now),
      record(time: now, succeeded: false, cost: null),
    ]);
    expect(summary.succeeded, 1);
    expect(summary.failed, 1);
    expect(summary.inputTokens, 2000);
    expect(summary.cachedTokens, 500);
    expect(summary.cacheHitRate, .25);
    expect(summary.averageCost, .01);
    expect(summary.requestsPerAnalysis, 2);
    expect(summary.modelTime, const Duration(seconds: 8));
    expect(summary.averageRequestTime, const Duration(seconds: 2));
    expect(summary.tokensPerSecond, 25);
  });

  test('空和不完整统计不产生虚假均价或缓存率', () {
    final empty = AiUsageSummary([]);
    expect(empty.averageCost, isNull);
    expect(empty.cacheHitRate, isNull);
    expect(empty.averageRequestTime, isNull);
    expect(empty.requestsPerAnalysis, isNull);
    final partial = AiUsageSummary([
      record(time: now, missing: true, cost: null),
    ]);
    expect(partial.cacheHitRate, isNull);
    expect(partial.averageCost, isNull);
    expect(partial.tokensPerSecond, isNull);
  });

  test('近七天包含今天和六天前，排除边界外及未来日期', () {
    final records = [
      record(time: DateTime(2026, 10, 28, 23, 59)),
      record(time: DateTime(2026, 10, 29)),
      record(time: DateTime(2026, 11, 4, 23, 59)),
      record(time: DateTime(2026, 11, 5)),
    ];
    expect(
      filterUsage(records, period: UsagePeriod.week, now: now),
      records.sublist(1, 3),
    );
    expect(filterUsage(records, period: UsagePeriod.today, now: now), [
      records[2],
    ]);
    expect(usagePeriodStart(UsagePeriod.month, now), DateTime(2026, 10, 6));
    expect(filterUsage(records, now: now), records);
  });

  test('模型和状态组合筛选', () {
    final records = [
      record(time: now),
      record(time: now, succeeded: false),
      record(time: now, model: 'model-b', succeeded: false),
    ];
    expect(
      filterUsage(
        records,
        model: 'model-a',
        status: UsageStatus.failed,
        now: now,
      ),
      [records[1]],
    );
    expect(filterUsage(records, status: UsageStatus.succeeded, now: now), [
      records[0],
    ]);
  });

  test('目录搜索不区分大小写，费用倒序且未知排在真实零费用之后', () {
    final records = [
      record(time: now, cost: null),
      record(time: now, cost: 0),
      record(time: now, cost: .2),
      record(time: now, directory: '/other/'),
    ];
    expect(sortUsage(records, query: ' SERIES ', sort: UsageSort.cost), [
      records[2],
      records[1],
      records[0],
    ]);
    expect(
      sortUsage([record(time: now), record(time: DateTime(2026, 11, 5))])
          .first
          .startedAt,
      DateTime(2026, 11, 5),
    );
  });

  test('按模型汇总，部分计价保留下界，未知费用排最后', () {
    final groups = usageByModel([
      record(time: now, model: 'unknown', cost: null),
      record(time: now, model: 'free', cost: 0),
      record(time: now, cost: .2),
      record(time: now, cost: null),
    ]);
    expect(groups.map((g) => g.model), ['model-a', 'free', 'unknown']);
    expect(groups.first.summary.analyses, 2);
    expect(groups.first.summary.pricedAnalyses, 1);
  });

  test('按本地日聚合并填补零用量日期', () {
    final days = usageByDay(
      [
        record(time: DateTime(2026, 11, 2)),
        record(time: DateTime(2026, 11, 2, 23, 59)),
        record(time: now),
      ],
      period: UsagePeriod.week,
      now: now,
    );
    expect(days.length, 7);
    expect(days.first.day, DateTime(2026, 10, 29));
    expect(days[4].summary.analyses, 2);
    expect(days[5].summary.analyses, 0);
    expect(days.last.summary.estimatedCost, .01);
    expect(usageByDay([], period: UsagePeriod.all, now: now), isEmpty);
  });
}
