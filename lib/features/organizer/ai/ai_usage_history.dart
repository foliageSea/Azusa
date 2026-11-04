import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../core/database/app_database.dart';
import 'ai_usage.dart';

class AiUsageRecord {
  const AiUsageRecord({
    required this.startedAt,
    required this.model,
    required this.directory,
    required this.usage,
    required this.succeeded,
    this.estimatedCost,
    this.priceSource,
  });

  final DateTime startedAt;
  final String model, directory;
  final AiUsage usage;
  final bool succeeded;
  // Snapshot the estimate so later catalog updates do not rewrite history.
  final double? estimatedCost;
  final String? priceSource;

  Map<String, dynamic> toJson() => {
    'startedAt': startedAt.toIso8601String(),
    'model': model,
    'directory': directory,
    'succeeded': succeeded,
    'estimatedCost': estimatedCost,
    'priceSource': priceSource,
    'inputTokens': usage.inputTokens,
    'outputTokens': usage.outputTokens,
    'cachedTokens': usage.cachedTokens,
    'modelTimeUs': usage.modelTime.inMicroseconds,
    'responses': usage.responses,
    'missingUsage': usage.missingUsage,
  };

  factory AiUsageRecord.fromJson(Map<String, dynamic> json) => AiUsageRecord(
    startedAt: DateTime.parse(json['startedAt'] as String),
    model: json['model'] as String,
    directory: json['directory'] as String,
    succeeded: json['succeeded'] as bool,
    estimatedCost: (json['estimatedCost'] as num?)?.toDouble(),
    priceSource: json['priceSource'] as String?,
    usage: AiUsage(
      inputTokens: json['inputTokens'] as int,
      outputTokens: json['outputTokens'] as int,
      cachedTokens: json['cachedTokens'] as int,
      modelTime: Duration(microseconds: json['modelTimeUs'] as int),
      responses: json['responses'] as int,
      missingUsage: json['missingUsage'] as bool,
    ),
  );
}

class AiUsageSummary {
  AiUsageSummary(Iterable<AiUsageRecord> records) {
    for (final record in records) {
      analyses++;
      if (record.succeeded) succeeded++;
      final usage = record.usage;
      inputTokens += usage.inputTokens;
      outputTokens += usage.outputTokens;
      cachedTokens += usage.cachedTokens;
      responses += usage.responses;
      modelTime += usage.modelTime;
      if (usage.missingUsage) missingUsage++;
      if (record.estimatedCost case final cost?) {
        estimatedCost += cost;
        pricedAnalyses++;
      }
      // Weight TPS by request time, not the number of analyses.
      if (usage.tokensPerSecond != null) {
        _timedOutput += usage.outputTokens;
        _modelTime += usage.modelTime;
      }
    }
  }

  int analyses = 0, responses = 0, inputTokens = 0, outputTokens = 0;
  int missingUsage = 0, pricedAnalyses = 0;
  int succeeded = 0, cachedTokens = 0;
  Duration modelTime = Duration.zero;
  double estimatedCost = 0;
  int _timedOutput = 0;
  Duration _modelTime = Duration.zero;

  int get failed => analyses - succeeded;
  double? get averageCost =>
      pricedAnalyses == 0 ? null : estimatedCost / pricedAnalyses;
  double? get requestsPerAnalysis =>
      analyses == 0 ? null : responses / analyses;
  double? get cacheHitRate =>
      inputTokens == 0 || missingUsage > 0 ? null : cachedTokens / inputTokens;
  Duration? get averageRequestTime => responses == 0
      ? null
      : Duration(microseconds: modelTime.inMicroseconds ~/ responses);

  double? get tokensPerSecond => _modelTime.inMicroseconds == 0
      ? null
      : _timedOutput *
            Duration.microsecondsPerSecond /
            _modelTime.inMicroseconds;
}

class AiUsageRepository {
  AiUsageRepository(this.database);

  final AppDatabase database;

  Future<List<AiUsageRecord>> load() async {
    final db = await database.connection();
    return db
        .select('SELECT * FROM ai_usage ORDER BY started_at_us DESC, id DESC')
        .map(
          (row) => AiUsageRecord(
            startedAt: DateTime.fromMicrosecondsSinceEpoch(
              row['started_at_us'] as int,
              isUtc: true,
            ),
            model: row['model'] as String,
            directory: row['directory'] as String,
            succeeded: row['succeeded'] == 1,
            estimatedCost: (row['estimated_cost'] as num?)?.toDouble(),
            priceSource: row['price_source'] as String?,
            usage: AiUsage(
              inputTokens: row['input_tokens'] as int,
              outputTokens: row['output_tokens'] as int,
              cachedTokens: row['cached_tokens'] as int,
              modelTime: Duration(microseconds: row['model_time_us'] as int),
              responses: row['responses'] as int,
              missingUsage: row['missing_usage'] == 1,
            ),
          ),
        )
        .toList();
  }

  Future<void> append(AiUsageRecord record) async {
    final db = await database.connection();
    _insert(db, record);
  }

  static void _insert(Database db, AiUsageRecord record) {
    final usage = record.usage;
    db.execute(
      '''
      INSERT INTO ai_usage (
        started_at_us, model, directory, succeeded, input_tokens,
        output_tokens, cached_tokens, model_time_us, responses,
        missing_usage, estimated_cost, price_source
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''',
      [
        record.startedAt.microsecondsSinceEpoch,
        record.model,
        record.directory,
        record.succeeded ? 1 : 0,
        usage.inputTokens,
        usage.outputTokens,
        usage.cachedTokens,
        usage.modelTime.inMicroseconds,
        usage.responses,
        usage.missingUsage ? 1 : 0,
        record.estimatedCost,
        record.priceSource,
      ],
    );
  }
}

final aiUsageRepositoryProvider = Provider<AiUsageRepository>(
  (ref) => AiUsageRepository(ref.watch(appDatabaseProvider)),
);
final aiUsageHistoryProvider = FutureProvider<List<AiUsageRecord>>(
  (ref) => ref.watch(aiUsageRepositoryProvider).load(),
);
