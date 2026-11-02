import 'dart:convert';
import 'dart:io';

import 'package:azusa/core/database/app_database.dart';
import 'package:azusa/features/organizer/ai/ai_usage.dart';
import 'package:azusa/features/organizer/ai/ai_usage_history.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

AiUsageRecord record({bool missing = false, double? cost = 0.01}) =>
    AiUsageRecord(
      startedAt: DateTime.utc(2026, 11, 2, 12),
      model: 'test-model',
      directory: '/dav/test/',
      usage: AiUsage(
        inputTokens: 1000,
        outputTokens: 100,
        cachedTokens: 200,
        responses: 2,
        modelTime: const Duration(seconds: 2),
        missingUsage: missing,
      ),
      succeeded: !missing,
      estimatedCost: cost,
      priceSource: cost == null ? null : 'openai/test-model',
    );

void main() {
  test('分析记录 JSON 完整往返，包括价格快照及失败记录', () {
    for (final original in [record(), record(missing: true, cost: null)]) {
      final restored = AiUsageRecord.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );
      expect(restored.toJson(), original.toJson());
    }
  });

  test('汇总包含失败记录，未知花费不当作免费，TPS 按时间加权', () {
    final summary = AiUsageSummary([
      record(),
      AiUsageRecord(
        startedAt: DateTime.now(),
        model: 'slow',
        directory: '/dav/',
        succeeded: false,
        usage: const AiUsage(
          inputTokens: 2000,
          outputTokens: 200,
          responses: 3,
          modelTime: Duration(seconds: 8),
        ),
      ),
      record(missing: true, cost: null),
    ]);
    expect(summary.analyses, 3);
    expect(summary.responses, 7);
    expect(summary.inputTokens, 4000);
    expect(summary.outputTokens, 400);
    expect(summary.tokensPerSecond, 30);
    expect(summary.pricedAnalyses, 1);
    expect(summary.estimatedCost, 0.01);
    expect(summary.missingUsage, 1);
  });

  test('空汇总和全部未知用量', () {
    final empty = AiUsageSummary([]);
    expect(empty.analyses, 0);
    expect(empty.estimatedCost, 0);
    expect(empty.tokensPerSecond, isNull);
    expect(AiUsageSummary([record(missing: true)]).tokensPerSecond, isNull);
  });

  test('本地记录重载及并发追加不丢失', () async {
    final directory = await Directory.systemTemp.createTemp('azu-sqlite-test-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/usage.sqlite3';
    final database = AppDatabase(open: () async => sqlite3.open(path));
    final repo = AiUsageRepository(database);
    addTearDown(database.close);
    expect(await repo.load(), isEmpty);
    await Future.wait([repo.append(record()), repo.append(record(cost: 0.02))]);
    await database.close();
    final reopenedDatabase = AppDatabase(open: () async => sqlite3.open(path));
    final reopened = AiUsageRepository(reopenedDatabase);
    addTearDown(reopenedDatabase.close);
    final loaded = await reopened.load();
    expect(loaded.length, 2);
    expect(AiUsageSummary(loaded).estimatedCost, closeTo(0.03, 1e-10));
    expect(loaded.first.toJson(), record(cost: 0.02).toJson());
  });

  test('存储失败向调用方报告且不阻塞后续写入', () async {
    var fails = true;
    final database = AppDatabase(
      open: () async {
        if (fails) throw StateError('open failed');
        return sqlite3.openInMemory();
      },
    );
    final repo = AiUsageRepository(database);
    addTearDown(database.close);
    await expectLater(repo.append(record()), throwsStateError);
    fails = false;
    await repo.append(record());
    expect((await repo.load()).length, 1);
  });

  test('关闭数据库后拒绝读写', () async {
    final database = AppDatabase(open: () async => sqlite3.openInMemory());
    final repo = AiUsageRepository(database);
    addTearDown(database.close);
    await repo.load();
    await database.close();
    await database.close();
    await expectLater(repo.load(), throwsStateError);
    await expectLater(repo.append(record()), throwsStateError);
  });
}
