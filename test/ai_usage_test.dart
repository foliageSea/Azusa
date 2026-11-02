import 'package:azusa/features/organizer/ai/ai_usage.dart';
import 'package:azusa/features/organizer/ai/model_pricing.dart';
import 'package:azusa/features/organizer/organizer_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  test('断开 NAS 后处于未连接状态', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(organizerProvider.notifier);
    controller.disconnect();
    expect(container.read(organizerProvider).directory, isEmpty);
    expect(container.read(organizerProvider).plan, isEmpty);
    expect(container.read(organizerProvider).aiUsage, isNull);
  });
  const price = ModelPricing(
    input: 2,
    output: 8,
    cacheRead: 0.5,
    source: 'test',
  );

  test('累加各轮输入输出和缓存，TPS 仅使用模型请求耗时', () {
    final usage = const AiUsage()
        .addResponse({
          'usage': {
            'prompt_tokens': 1000,
            'completion_tokens': 100,
            'prompt_tokens_details': {'cached_tokens': 400},
          },
        }, const Duration(seconds: 2))
        .addResponse({
          'usage': {'prompt_tokens': 2000, 'completion_tokens': 200},
        }, const Duration(seconds: 4));
    expect(usage.inputTokens, 3000);
    expect(usage.outputTokens, 300);
    expect(usage.cachedTokens, 400);
    expect(usage.tokensPerSecond, 50);
    expect(price.estimate(usage), closeTo(0.0078, 1e-10));
  });

  test('缺失用量不伪造零花费，真实免费价格保留为零', () {
    expect(price.estimate(const AiUsage()), isNull);
    final unknown = const AiUsage().addResponse({}, const Duration(seconds: 1));
    expect(unknown.missingUsage, isTrue);
    expect(unknown.tokensPerSecond, isNull);
    expect(price.estimate(unknown), isNull);
    const free = ModelPricing(input: 0, output: 0, source: 'free');
    expect(free.estimate(const AiUsage(responses: 1, inputTokens: 10)), 0);
  });

  final catalog = <String, dynamic>{
    'openai': {
      'models': {
        'gpt-test': {
          'cost': {'input': 2, 'output': 8, 'cache_read': 0.5},
        },
      },
    },
    'relay': {
      'api': 'https://relay.test/v1',
      'models': {
        'gpt-test': {
          'cost': {'input': 3, 'output': 10},
        },
      },
    },
  };

  test('优先匹配服务商端点，自定义地址使用原厂参考价格', () {
    final relay = ModelPricingCatalog.match(
      catalog,
      'https://relay.test/v1/',
      'gpt-test',
    );
    expect(relay?.input, 3);
    final reference = ModelPricingCatalog.match(
      catalog,
      'https://custom.test/v1',
      'gpt-test',
    );
    expect(reference?.input, 2);
    expect(reference?.cacheRead, 0.5);
    expect(
      ModelPricingCatalog.match(catalog, 'https://custom.test/v1', 'unknown'),
      isNull,
    );
    expect(
      ModelPricingCatalog.match(
        catalog,
        'https://custom.test/v1',
        'relay/gpt-test',
      )?.input,
      3,
    );
  });

  test('没有价格或匹配歧义时返回未知', () {
    final ambiguous = {...catalog, 'anthropic': catalog['openai']};
    expect(
      ModelPricingCatalog.match(
        ambiguous,
        'https://custom.test/v1',
        'gpt-test',
      ),
      isNull,
    );
    expect(
      ModelPricingCatalog.match(
        {
          'openai': {
            'models': {'x': {}},
          },
        },
        '',
        'x',
      ),
      isNull,
    );
  });

  test('分析用量随状态更新保留，切换目录或重新分析清除', () {
    const state = OrganizerState(
      aiUsage: AiUsage(responses: 1),
      pricing: price,
    );
    expect(state.copyWith(busy: true).pricing, price);
    expect(state.copyWith(clearAnalysis: true).aiUsage, isNull);
    expect(state.copyWith(clearAnalysis: true).pricing, isNull);
  });
}
