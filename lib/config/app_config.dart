class AppConfig {
  AppConfig._();
  // Override at build time: flutter run --dart-define=HI_DOC_BACKEND_URL=http://192.168.1.10:4000
  static String backendBaseUrl = const String.fromEnvironment(
    'HI_DOC_BACKEND_URL',
    defaultValue: 'http://localhost:4000',
  );



  static String openAiModel = const String.fromEnvironment(
    'OPENAI_MODEL',
    defaultValue: 'gpt-3.5-turbo',
  );
  
  static const msTokenExchangePath = '/api/auth/microsoft/exchange';
  static Uri microsoftExchangeUri() => Uri.parse('$backendBaseUrl$msTokenExchangePath');
}
