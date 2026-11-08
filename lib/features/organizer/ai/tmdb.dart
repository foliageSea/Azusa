import 'package:dio/dio.dart';

import '../../../core/settings/naming_language.dart';
import '../connections/connection_settings.dart';
import '../connections/http_clients.dart';

class TmdbClient {
  TmdbClient(
    ConnectionSettings settings, {
    Dio? client,
    this.namingLanguage = NamingLanguage.simplifiedChinese,
  }) : token = settings.tmdbToken,
       dio =
           client ??
           createServiceClient(settings, service: NetworkService.tmdb);
  final String token;
  final NamingLanguage namingLanguage;
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
      queryParameters: parameters({
        'query': query,
        'language': namingLanguage.code,
      }),
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

  Future<List<Map<String, dynamic>>> searchMovies(
    String query, {
    int? year,
  }) async {
    if (token.isEmpty) throw StateError('请配置 TMDB Token');
    if (query.trim().isEmpty ||
        query.length > 200 ||
        (year != null && (year < 1 || year > 9999))) {
      throw const FormatException('电影查询无效');
    }
    final response = await dio.get<Map<String, dynamic>>(
      'https://api.themoviedb.org/3/search/movie',
      queryParameters: parameters({
        'query': query,
        'language': namingLanguage.code,
        'year': ?year,
      }),
      options: options,
    );
    return (response.data?['results'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .take(10)
        .map(_movieFields)
        .toList();
  }

  static Map<String, dynamic> _movieFields(Map<String, dynamic> movie) => {
    for (final key in [
      'id',
      'title',
      'original_title',
      'release_date',
      'overview',
    ])
      key: movie[key],
  };

  Future<Map<String, dynamic>> movie(int id) async {
    if (token.isEmpty) throw StateError('请配置 TMDB Token');
    if (id < 1) throw const FormatException('电影编号无效');
    final response = await dio.get<Map<String, dynamic>>(
      'https://api.themoviedb.org/3/movie/$id',
      queryParameters: parameters({'language': namingLanguage.code}),
      options: options,
    );
    final data = response.data;
    if (data == null ||
        data['id'] != id ||
        ![
          data['title'],
          data['original_title'],
        ].any((value) => value is String && value.trim().isNotEmpty)) {
      throw const FormatException('TMDB 电影详情无效');
    }
    return _movieFields(data);
  }

  Future<List<Map<String, dynamic>>> season(int id, int number) async {
    if (token.isEmpty) throw StateError('请配置 TMDB Token');
    if (id < 1 || number < 0 || number > 1000) {
      throw const FormatException('剧集或季编号无效');
    }
    final response = await dio.get<Map<String, dynamic>>(
      'https://api.themoviedb.org/3/tv/$id/season/$number',
      queryParameters: parameters({'language': namingLanguage.code}),
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

  Future<Map<String, dynamic>> _details(
    String path,
    int id, {
    String? append,
  }) async {
    if (token.isEmpty) throw StateError('请配置 TMDB Token');
    final response = await dio.get<Map<String, dynamic>>(
      'https://api.themoviedb.org/3/$path',
      queryParameters: parameters({
        'language': namingLanguage.code,
        'append_to_response': ?append,
      }),
      options: options,
    );
    final data = response.data;
    if (data == null || data['id'] != id) {
      throw const FormatException('TMDB 详情无效');
    }
    return data;
  }

  /// Full movie details with credits, used to write metadata files.
  Future<Map<String, dynamic>> movieMetadata(int id) {
    if (id < 1) throw const FormatException('电影编号无效');
    return _details('movie/$id', id, append: 'credits');
  }

  /// Full series details with credits and external ids.
  Future<Map<String, dynamic>> tvMetadata(int id) {
    if (id < 1) throw const FormatException('剧集或季编号无效');
    return _details('tv/$id', id, append: 'credits,external_ids');
  }

  /// Full season details, including episode overviews and stills.
  Future<Map<String, dynamic>> seasonMetadata(int id, int number) async {
    if (token.isEmpty) throw StateError('请配置 TMDB Token');
    if (id < 1 || number < 0 || number > 1000) {
      throw const FormatException('剧集或季编号无效');
    }
    final response = await dio.get<Map<String, dynamic>>(
      'https://api.themoviedb.org/3/tv/$id/season/$number',
      queryParameters: parameters({'language': namingLanguage.code}),
      options: options,
    );
    final data = response.data;
    if (data == null) throw const FormatException('TMDB 详情无效');
    return data;
  }

  static final _imagePath = RegExp(r'^/[A-Za-z0-9_-]+\.(?:jpe?g|png|webp)$');

  static bool validImagePath(Object? path) =>
      path is String && _imagePath.hasMatch(path);

  /// Downloads a TMDB image. Only TMDB-issued relative paths are accepted.
  Future<List<int>> image(String path, {String size = 'original'}) async {
    if (!validImagePath(path) ||
        !RegExp(r'^(?:original|w\d{2,4})$').hasMatch(size)) {
      throw const FormatException('TMDB 图片地址无效');
    }
    final response = await dio.get<List<int>>(
      'https://image.tmdb.org/t/p/$size$path',
      options: Options(responseType: ResponseType.bytes),
    );
    final data = response.data;
    if (data == null || data.isEmpty) {
      throw const FormatException('TMDB 图片下载失败');
    }
    return data;
  }

  void close() => dio.close(force: true);
}
