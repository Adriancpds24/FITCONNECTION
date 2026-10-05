class ApiKeys {
  // Para usar el chatbot de nutrición, necesitas una de estas API keys:

  // Opción 1: Google Gemini Pro Vision (Recomendado - Gratis y más fácil)
  // 1. Ve a https://makersuite.google.com/app/apikey
  // 2. Crea una nueva API key
  // 3. Reemplaza 'YOUR_GEMINI_API_KEY' con tu key
  static const String geminiApiKey = 'YOUR_GEMINI_API_KEY';

  // Opción 2: OpenAI GPT-4o (Requiere tarjeta de crédito)
  // 1. Ve a https://platform.openai.com/api-keys
  // 2. Crea una nueva API key
  // 3. Reemplaza 'YOUR_OPENAI_API_KEY' con tu key
  static const String openAIApiKey = 'YOUR_OPENAI_API_KEY';

  // Método para obtener la API key activa
  static String getActiveKey() {
    // Priorizamos Gemini porque es gratis y más fácil de configurar
    if (geminiApiKey != 'YOUR_GEMINI_API_KEY' && geminiApiKey.isNotEmpty) {
      return geminiApiKey;
    }

    if (openAIApiKey != 'YOUR_OPENAI_API_KEY' && openAIApiKey.isNotEmpty) {
      return openAIApiKey;
    }

    throw Exception(
      'No hay ninguna API key configurada. Por favor, configura tu API key en lib/core/config/api_keys.dart',
    );
  }

  static bool isConfigured() {
    return (geminiApiKey != 'YOUR_GEMINI_API_KEY' && geminiApiKey.isNotEmpty) ||
        (openAIApiKey != 'YOUR_OPENAI_API_KEY' && openAIApiKey.isNotEmpty);
  }
}
