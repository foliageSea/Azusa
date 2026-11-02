import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';

/// Keeps the original record text and insertion order for HistoryEntry pairing.
class ExecutionHistoryRepository {
  ExecutionHistoryRepository(this.database);

  final AppDatabase database;

  Future<List<String>> load() async {
    final db = await database.connection();
    return db
        .select('SELECT record FROM execution_history ORDER BY id ASC')
        .map((row) => row['record'] as String)
        .toList();
  }

  Future<void> append(String record) async {
    final db = await database.connection();
    db.execute('INSERT INTO execution_history (record) VALUES (?)', [record]);
  }
}

final executionHistoryRepositoryProvider = Provider<ExecutionHistoryRepository>(
  (ref) => ExecutionHistoryRepository(ref.watch(appDatabaseProvider)),
);
