/// Configuration for on-device LLaMA inference.
class LocalAiConfig {
  /// Max tokens to generate for a single parse response.
  static int maxTokens = 320;

  /// Sampling temperature (lower => more deterministic JSON).
  static double temperature = 0.15;

  /// top-p nucleus sampling.
  static double topP = 0.9;

  /// Optional top-k.
  static int topK = 40;

  /// Repeat penalty.
  static double repeatPenalty = 1.05;

  /// Model file name inside assets/models and later documents directory.
  static String modelFileName = 'tinyllama.gguf';

  /// Whether to attempt local model first.
  static bool enableLocalFirst = true;
}
