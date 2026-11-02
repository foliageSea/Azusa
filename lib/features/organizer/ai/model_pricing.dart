import 'package:dio/dio.dart';

import 'ai_usage.dart';
import '../connections/connection_settings.dart';
import '../connections/http_clients.dart';

class ModelPricingCatalog {
  static const _firstParty = {
    'openai',
    'anthropic',
    'google',
    'deepseek',
    'xai',
    'mistral',
    'moonshotai',
    'minimax',
    'zhipuai',
    'alibaba',
  };
  static Map<String, dynamic>? _cached;
  static DateTime? _loadedAt;

  /// Pricing failure must never prevent analysis. No AI credentials are sent.
  static Future<ModelPricing?> lookup(ConnectionSettings settings) async {
    Dio? client;
    try {
      if (_cached == null ||
          DateTime.now().difference(_loadedAt!) > const Duration(hours: 24)) {
        client = createServiceClient(
          settings,
          timeout: const Duration(seconds: 8),
        );
        final response = await client.get<Map<String, dynamic>>(
          'https://models.dev/api.json',
        );
        _cached = response.data;
        _loadedAt = DateTime.now();
      }
      return match(_cached ?? {}, settings.aiUrl, settings.model);
    } catch (_) {
      return match(_cached ?? {}, settings.aiUrl, settings.model);
    } finally {
      client?.close(force: true);
    }
  }

  static ModelPricing? match(
    Map<String, dynamic> catalog,
    String baseUrl,
    String modelId,
  ) {
    final endpoint = Uri.tryParse(baseUrl);
    final candidates = <({int priority, ModelPricing price})>[];
    for (final entry in catalog.entries) {
      final provider = entry.value;
      if (provider is! Map || provider['models'] is! Map) continue;
      final models = provider['models'] as Map;
      final prefix = '${entry.key}/';
      final localId = modelId.startsWith(prefix)
          ? modelId.substring(prefix.length)
          : modelId;
      final model = models[modelId] ?? models[localId];
      if (model is! Map) continue;
      final cost = model['cost'];
      if (cost is! Map || cost['input'] is! num || cost['output'] is! num) {
        continue;
      }
      double? rate(Object? value) =>
          value is num && value.isFinite && value >= 0
          ? value.toDouble()
          : null;
      final input = rate(cost['input']);
      final output = rate(cost['output']);
      if (input == null || output == null) continue;
      final api = Uri.tryParse(
        provider['api'] as String? ??
            (entry.key == 'openai' ? 'https://api.openai.com/v1' : ''),
      );
      final sameEndpoint =
          endpoint != null &&
          api != null &&
          api.hasAuthority &&
          endpoint.origin == api.origin &&
          (endpoint.path.replaceFirst(RegExp(r'/+$'), '') ==
                  api.path.replaceFirst(RegExp(r'/+$'), '') ||
              api.path.isEmpty && endpoint.path == '/v1');
      final canonical = model['canonical_model_id'];
      final priority = sameEndpoint
          ? 3
          : modelId.startsWith(prefix)
          ? 2
          : canonical == '${entry.key}/$localId' ||
                _firstParty.contains(entry.key)
          ? 1
          : 0;
      if (priority == 0) continue;
      candidates.add((
        priority: priority,
        price: ModelPricing(
          input: input,
          output: output,
          cacheRead: rate(cost['cache_read']),
          source: '${entry.key}/$localId',
        ),
      ));
    }
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => b.priority.compareTo(a.priority));
    if (candidates.length > 1 &&
        candidates[0].priority == candidates[1].priority) {
      return null;
    }
    return candidates.first.price;
  }
}
