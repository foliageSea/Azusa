import 'package:azusa/features/organizer/connections/ai_models.dart';
import 'package:azusa/features/organizer/connections/connection_settings.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'network_services_test.dart' show TestAdapter, jsonResponse;

void main() {
  test('模型请求保留基础路径、携带认证并将有效 ID 去重排序', () async {
    final dio = Dio()
      ..httpClientAdapter = TestAdapter((options) {
        expect(options.uri.toString(), 'https://ai.test/custom/v1/models');
        expect(options.headers['Authorization'], 'Bearer test-key');
        return jsonResponse({
          'data': [
            {'id': 'model-z'},
            {'id': ' model-a '},
            {'id': 'model-z'},
            {'id': ''},
            {'id': 42},
            {'name': 'not-an-id'},
            null,
          ],
        });
      });
    addTearDown(() => dio.close(force: true));
    expect(
      await fetchAiModels(
        const ConnectionSettings(
          aiUrl: 'https://ai.test/custom/v1///',
          aiKey: 'test-key',
        ),
        client: dio,
      ),
      ['model-a', 'model-z'],
    );
  });

  test('无密钥的兼容服务不发送认证头，支持空模型列表', () async {
    final dio = Dio()
      ..httpClientAdapter = TestAdapter((options) {
        expect(options.uri.toString(), 'http://localhost:1234/models');
        expect(options.headers.containsKey('Authorization'), isFalse);
        return jsonResponse({'data': []});
      });
    addTearDown(() => dio.close(force: true));
    expect(
      await fetchAiModels(
        const ConnectionSettings(aiUrl: 'http://localhost:1234/'),
        client: dio,
      ),
      isEmpty,
    );
  });

  for (final body in <Object>[
    [],
    {},
    {'data': 'invalid'},
  ]) {
    test('拒绝无效模型响应 $body', () async {
      final dio = Dio()
        ..httpClientAdapter = TestAdapter((_) => jsonResponse(body));
      addTearDown(() => dio.close(force: true));
      await expectLater(
        fetchAiModels(const ConnectionSettings(), client: dio),
        throwsFormatException,
      );
    });
  }

  test('认证失败向调用方传播', () async {
    final dio = Dio()
      ..httpClientAdapter = TestAdapter(
        (_) => ResponseBody.fromString('', 401),
      );
    addTearDown(() => dio.close(force: true));
    await expectLater(
      fetchAiModels(const ConnectionSettings(), client: dio),
      throwsA(
        isA<DioException>().having(
          (e) => e.response?.statusCode,
          'statusCode',
          401,
        ),
      ),
    );
  });
}
