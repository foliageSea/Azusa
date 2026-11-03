import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'connection_settings.dart';
import 'http_clients.dart';

final aiModelsLoaderProvider =
    Provider<Future<List<String>> Function(ConnectionSettings)>(
      (ref) =>
          (settings) => fetchAiModels(settings),
    );

Future<List<String>> fetchAiModels(
  ConnectionSettings settings, {
  Dio? client,
}) async {
  final base = validatedHttpUrl(settings.aiUrl, allowHttp: true);
  final dio = client ?? createServiceClient(settings);
  try {
    final response = await dio.getUri<Object>(
      base.replace(
        path: '${base.path.replaceFirst(RegExp(r'/+$'), '')}/models',
      ),
      options: Options(
        headers: {
          if (settings.aiKey.isNotEmpty)
            'Authorization': 'Bearer ${settings.aiKey}',
        },
      ),
    );
    final body = response.data;
    if (body is! Map || body['data'] is! List) {
      throw const FormatException('AI /models 未返回有效 JSON');
    }
    final ids = <String>{};
    for (final item in body['data'] as List) {
      if (item is Map && item['id'] is String) {
        final id = (item['id'] as String).trim();
        if (id.isNotEmpty) ids.add(id);
      }
    }
    return ids.toList()..sort();
  } finally {
    if (client == null) dio.close(force: true);
  }
}
