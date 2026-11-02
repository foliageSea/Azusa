/// Usage reported by the API, accumulated across all model/tool rounds.
class AiUsage {
  const AiUsage({
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cachedTokens = 0,
    this.modelTime = Duration.zero,
    this.responses = 0,
    this.missingUsage = false,
  });

  final int inputTokens, outputTokens, cachedTokens, responses;
  final Duration modelTime;
  final bool missingUsage;

  double? get tokensPerSecond =>
      responses == 0 || missingUsage || modelTime.inMicroseconds == 0
      ? null
      : outputTokens *
            Duration.microsecondsPerSecond /
            modelTime.inMicroseconds;

  AiUsage addResponse(Map<String, dynamic> body, Duration elapsed) {
    final usage = body['usage'];
    final input = usage is Map ? usage['prompt_tokens'] : null;
    final output = usage is Map ? usage['completion_tokens'] : null;
    final details = usage is Map ? usage['prompt_tokens_details'] : null;
    final cached = details is Map ? details['cached_tokens'] : null;
    final valid = input is int && input >= 0 && output is int && output >= 0;
    return AiUsage(
      inputTokens: inputTokens + (valid ? input : 0),
      outputTokens: outputTokens + (valid ? output : 0),
      cachedTokens:
          cachedTokens + (valid && cached is int ? cached.clamp(0, input) : 0),
      responses: responses + 1,
      modelTime: modelTime + elapsed,
      missingUsage: missingUsage || !valid,
    );
  }
}

class ModelPricing {
  const ModelPricing({
    required this.input,
    required this.output,
    this.cacheRead,
    required this.source,
  });

  final double input, output;
  final double? cacheRead;
  final String source;

  double? estimate(AiUsage usage) {
    if (usage.responses == 0 || usage.missingUsage) return null;
    return ((usage.inputTokens - usage.cachedTokens) * input +
            usage.cachedTokens * (cacheRead ?? input) +
            usage.outputTokens * output) /
        1000000;
  }
}
