import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../connections/connection_settings.dart';
import 'dav_paths.dart';
import '../connections/http_clients.dart';

typedef NasScope = ({String endpoint, String username});

NasScope nasScope(ConnectionSettings settings) {
  final uri = validatedHttpUrl(settings.webdavUrl, allowHttp: true);
  final root = favoriteDirectory(uri.path.isEmpty ? '/' : uri.path);
  return (endpoint: '${uri.origin}$root', username: settings.username);
}

String favoriteDirectory(String path) {
  final canonical = canonicalDavPath(path);
  if (canonical.contains('//')) throw const FormatException('目录路径无效');
  return canonical.endsWith('/') ? canonical : '$canonical/';
}

class DirectoryFavoritesRepository {
  DirectoryFavoritesRepository(this.database);

  final AppDatabase database;

  String _validate(NasScope scope, String path) {
    final directory = favoriteDirectory(path);
    final root = favoriteDirectory(Uri.parse(scope.endpoint).path);
    if (!directory.startsWith(root)) {
      throw const FormatException('收藏目录超出 NAS 根目录');
    }
    return directory;
  }

  Future<List<String>> load(NasScope scope) async {
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

  Future<void> add(NasScope scope, String path) async {
    final directory = _validate(scope, path);
    final db = await database.connection();
    db.execute(
      'INSERT OR IGNORE INTO directory_favorites (endpoint, username, path) VALUES (?, ?, ?)',
      [scope.endpoint, scope.username, directory],
    );
  }

  Future<void> remove(NasScope scope, String path) async {
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
    FutureProvider.family<List<String>, NasScope>(
      (ref, scope) =>
          ref.watch(directoryFavoritesRepositoryProvider).load(scope),
    );
