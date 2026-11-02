import 'package:dio/dio.dart';

import '../connections/connection_settings.dart';
import '../connections/http_clients.dart';

class TmdbClient {
  TmdbClient(ConnectionSettings settings, {Dio? client})
    : token = settings.tmdbToken,
      dio =
          client ?? createServiceClient(settings, service: NetworkService.tmdb);
  final String token;
  final Dio dio;

  bool get usesBearer => token.split('.').length == 3;
  Options get options =>
      Options(headers: {if (usesBearer) 'Authorization': 'Bearer $token'});
  Map<String, dynamic> parameters(Map<String, dynamic> values) => {
    if (!usesBearer) 'api_key': token,
    ...values,
  };

  Future<List<Map<String, dynamic>>> search(String query) async {
    if (token.isEmpty) throw StateError('请配置 TMDB Token');
    if (query.trim().isEmpty || query.length > 200) {
      throw const FormatException('剧集查询无效');
    }
    final response = await dio.get<Map<String, dynamic>>(
      'https://api.themoviedb.org/3/search/tv',
      queryParameters: parameters({'query': query, 'language': 'zh-CN'}),
      options: options,
    );
    return (response.data?['results'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .take(10)
        .map(
          (e) => {
            for (final key in [
              'id',
              'name',
              'original_name',
              'first_air_date',
              'origin_country',
              'overview',
            ])
              key: e[key],
          },
        )
        .toList();
  }

  Future<List<Map<String, dynamic>>> season(int id, int number) async {
    if (token.isEmpty) throw StateError('请配置 TMDB Token');
    if (id < 1 || number < 0 || number > 1000) {
      throw const FormatException('剧集或季编号无效');
    }
    final response = await dio.get<Map<String, dynamic>>(
      'https://api.themoviedb.org/3/tv/$id/season/$number',
      queryParameters: parameters({'language': 'zh-CN'}),
      options: options,
    );
    return (response.data?['episodes'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .map(
          (e) => {
            for (final key in [
              'id',
              'name',
              'episode_number',
              'season_number',
              'air_date',
            ])
              key: e[key],
          },
        )
        .toList();
  }

  void close() => dio.close(force: true);
}
