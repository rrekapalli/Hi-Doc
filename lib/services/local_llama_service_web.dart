// Web stub for LocalLlamaService - always returns null; llama_cpp_dart unsupported on web.
import '../models/parsed_parameter.dart';

class LocalLlamaService {
  static final LocalLlamaService _instance = LocalLlamaService._internal();
  factory LocalLlamaService() => _instance;
  LocalLlamaService._internal();
  Future<List<ParsedParameter>?> parseMessage(String message) async => null;
}
