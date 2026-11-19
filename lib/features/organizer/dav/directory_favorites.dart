import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../file_server/file_server.dart';
import '../file_server/file_server_paths.dart';

String favoriteDirectory(String path) {
  final canonical = canonicalFileServerPath(path);
  if (canonical.contains('//')) throw const FormatException('目录路径无效');
  return canonical.endsWith('/') ? canonical : '$canonical/';
}

class DirectoryFavoritesRepository {
  DirectoryFavoritesRepository(this.database);

  final AppDatabase database;

  String _validate(FileServerScope scope, String path) {
    final directory = favoriteDirectory(path);
    final root = favoriteDirectory(scope.root);
    if (!directory.startsWith(root)) {
      throw const FormatException('收藏目录超出文件服务器根目录');
    }
    return directory;
  }

  Future<List<String>> load(FileServerScope scope) async {
    final db = await database.connection();
    return db
        .select(
          '''
      SELECT path FROM directory_favorites
      WHERE endpoint = ? AND username = ? ORDER BY id ASC
    ''',
          [scope.endpoint, scope.username],
        )
        .map((row) => _validate(scope, row['path'] as String))
        .toList();
  }

  Future<void> add(FileServerScope scope, String path) async {
    final directory = _validate(scope, path);
    final db = await database.connection();
    db.execute(
      'INSERT OR IGNORE INTO directory_favorites (endpoint, username, path) VALUES (?, ?, ?)',
      [scope.endpoint, scope.username, directory],
    );
  }

  Future<void> remove(FileServerScope scope, String path) async {
    final directory = _validate(scope, path);
    final db = await database.connection();
    db.execute(
      'DELETE FROM directory_favorites WHERE endpoint = ? AND username = ? AND path = ?',
      [scope.endpoint, scope.username, directory],
    );
  }
}

final directoryFavoritesRepositoryProvider =
    Provider<DirectoryFavoritesRepository>(
      (ref) => DirectoryFavoritesRepository(ref.watch(appDatabaseProvider)),
    );

final directoryFavoritesProvider =
    FutureProvider.family<List<String>, FileServerScope>(
      (ref, scope) =>
          ref.watch(directoryFavoritesRepositoryProvider).load(scope),
    );
