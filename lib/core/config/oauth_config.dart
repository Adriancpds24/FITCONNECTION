/// IDs de OAuth (Google / Apple) vía `--dart-define=...` en build/run.
class OauthConfig {
  /// ID de cliente **Web** de Google Cloud (OAuth 2.0). Debe coincidir con el
  /// configurado en el servidor en `GOOGLE_OAUTH_CLIENT_IDS` o `GOOGLE_WEB_CLIENT_ID`.
  static const String googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '',
  );
}
