import 'ai_usage_history.dart';

enum UsagePeriod { today, week, month, all }

enum UsageStatus { all, succeeded, failed }

enum UsageSort { newest, cost }

/// Calendar-day boundaries follow the user's local timezone.
DateTime usageDay(DateTime date) {
  final local = date.toLocal();
  return DateTime(local.year, local.month, local.day);
}

DateTime? usagePeriodStart(UsagePeriod period, DateTime now) {
  final today = usageDay(now);
  return switch (period) {
    UsagePeriod.today => today,
    UsagePeriod.week => DateTime(today.year, today.month, today.day - 6),
    UsagePeriod.month => DateTime(today.year, today.month, today.day - 29),
    UsagePeriod.all => null,
  };
}

List<AiUsageRecord> filterUsage(
  Iterable<AiUsageRecord> records, {
  UsagePeriod period = UsagePeriod.all,
  UsageStatus status = UsageStatus.all,
  String? model,
  required DateTime now,
}) {
  final start = usagePeriodStart(period, now);
  final today = usageDay(now);
  final end = DateTime(today.year, today.month, today.day + 1);
  return records.where((record) {
    final date = record.startedAt.toLocal();
    return (start == null || (!date.isBefore(start) && date.isBefore(end))) &&
        (model == null || record.model == model) &&
        switch (status) {
          UsageStatus.all => true,
          UsageStatus.succeeded => record.succeeded,
          UsageStatus.failed => !record.succeeded,
        };
  }).toList();
}

List<AiUsageRecord> sortUsage(
  Iterable<AiUsageRecord> records, {
  String query = '',
  UsageSort sort = UsageSort.newest,
}) {
  final search = query.trim().toLowerCase();
  return records
      .where((record) => record.directory.toLowerCase().contains(search))
      .toList()
    ..sort((a, b) {
      if (sort == UsageSort.cost) {
        // Unknown prices are not zero-cost records; keep them last.
        if (a.estimatedCost == null && b.estimatedCost != null) return 1;
        if (a.estimatedCost != null && b.estimatedCost == null) return -1;
        final cost = (b.estimatedCost ?? 0).compareTo(a.estimatedCost ?? 0);
        if (cost != 0) return cost;
      }
      return b.startedAt.compareTo(a.startedAt);
    });
}

class UsageModelGroup {
  UsageModelGroup(this.model, Iterable<AiUsageRecord> records)
    : summary = AiUsageSummary(records);

  final String model;
  final AiUsageSummary summary;
}

List<UsageModelGroup> usageByModel(Iterable<AiUsageRecord> records) {
  final groups = <String, List<AiUsageRecord>>{};
  for (final record in records) {
    (groups[record.model] ??= []).add(record);
  }
  return [
    for (final entry in groups.entries) UsageModelGroup(entry.key, entry.value),
  ]..sort((a, b) {
    final known = (b.summary.pricedAnalyses > 0 ? 1 : 0).compareTo(
      a.summary.pricedAnalyses > 0 ? 1 : 0,
    );
    if (known != 0) return known;
    final cost = b.summary.estimatedCost.compareTo(a.summary.estimatedCost);
    return cost == 0 ? a.model.compareTo(b.model) : cost;
  });
}

class UsageDayGroup {
  UsageDayGroup(this.day, Iterable<AiUsageRecord> records)
    : summary = AiUsageSummary(records);

  final DateTime day;
  final AiUsageSummary summary;
}

List<UsageDayGroup> usageByDay(
  Iterable<AiUsageRecord> records, {
  required UsagePeriod period,
  required DateTime now,
}) {
  final groups = <DateTime, List<AiUsageRecord>>{};
  for (final record in records) {
    (groups[usageDay(record.startedAt)] ??= []).add(record);
  }
  final days = groups.keys.toList()..sort();
  final start =
      usagePeriodStart(period, now) ?? (days.isEmpty ? null : days.first);
  if (start == null) return [];
  final today = usageDay(now);
  final end = days.isNotEmpty && days.last.isAfter(today) ? days.last : today;
  return [
    for (
      var day = start;
      !day.isAfter(end);
      day = DateTime(day.year, day.month, day.day + 1)
    )
      UsageDayGroup(day, groups[day] ?? const []),
  ];
}
