import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;

/// Routes the LangChain OpenAI transport through the application's Dio client.
/// This preserves per-service proxies, timeouts, and redirect restrictions.
class LangChainHttpClient extends http.BaseClient {
  LangChainHttpClient(this.dio, {this.onChatRequest, this.onChatResponse});

  final Dio dio;
  final void Function()? onChatRequest;
  final void Function(Map<String, dynamic> body, Duration elapsed)?
  onChatResponse;
  bool _closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) throw http.ClientException('AI 客户端已关闭');
    final chat = request.url.path.endsWith('/chat/completions');
    if (chat) onChatRequest?.call();
    final watch = Stopwatch()..start();
    final response = await dio.requestUri<ResponseBody>(
      request.url,
      data: request.finalize(),
      options: Options(
        method: request.method,
        headers: {
          ...request.headers,
          if (request.contentLength != null)
            'Content-Length': '${request.contentLength}',
        },
        responseType: ResponseType.stream,
        followRedirects: false,
        // Let the OpenAI SDK parse HTTP errors, but never follow redirects.
        validateStatus: (status) => status != null,
      ),
    );
    final body = response.data!;
    Stream<List<int>> observed() async* {
      final bytes = <int>[];
      await for (final chunk in body.stream) {
        bytes.addAll(chunk);
        yield chunk;
      }
      watch.stop();
      if (response.statusCode! >= 200 && response.statusCode! < 300) {
        Map<String, dynamic> decoded = const {};
        try {
          final value = jsonDecode(utf8.decode(bytes));
          if (value is Map<String, dynamic>) decoded = value;
        } on FormatException {
          // Unknown response formats remain usable by the SDK, without metrics.
        }
        onChatResponse?.call(decoded, watch.elapsed);
      }
    }

    return http.StreamedResponse(
      chat && onChatResponse != null ? observed() : body.stream,
      response.statusCode!,
      headers: body.headers.map(
        (key, values) => MapEntry(key, values.join(',')),
      ),
      contentLength: int.tryParse(
        response.headers.value('content-length') ?? '',
      ),
      request: request,
      reasonPhrase: response.statusMessage,
    );
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    dio.close(force: true);
    super.close();
  }
}
