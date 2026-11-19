import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import 'history_entry.dart';

/// Keeps the original record text and insertion order for HistoryEntry pairing.
class ExecutionHistoryRepository {
  ExecutionHistoryRepository(this.database);

  final AppDatabase database;

  Future<List<ExecutionHistoryRecord>> load() async {
    final db = await database.connection();
    return [
      for (final row in db.select('''
        SELECT record, connection_id, server_name, server_protocol
        FROM execution_history ORDER BY id ASC
      '''))
        ExecutionHistoryRecord(
          row['record'] as String,
          server: switch ((
            row['connection_id'],
            row['server_name'],
            row['server_protocol'],
          )) {
            (final String id, final String name, final String protocol) =>
              HistoryServer(connectionId: id, name: name, protocol: protocol),
            _ => null,
          },
        ),
    ];
  }

  Future<void> append(String record, {HistoryServer? server}) async {
    final db = await database.connection();
    db.execute(
      '''
      INSERT INTO execution_history (record, connection_id, server_name, server_protocol)
      VALUES (?, ?, ?, ?)
    ''',
      [record, server?.connectionId, server?.name, server?.protocol],
    );
  }
}

final executionHistoryRepositoryProvider = Provider<ExecutionHistoryRepository>(
  (ref) => ExecutionHistoryRepository(ref.watch(appDatabaseProvider)),
);
