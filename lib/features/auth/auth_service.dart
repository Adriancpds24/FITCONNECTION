import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'package:rms/core/config/oauth_config.dart';
import 'package:rms/core/constants/api_constants.dart';
import 'package:rms/features/chat/chat_realtime_service.dart';
import 'package:rms/features/social/post_model.dart';
import 'package:rms/features/social/social_state.dart';
import 'package:rms/core/theme/theme_provider.dart';

class AuthException implements Exception {
  final String message;
  final String? code;

  AuthException(this.message, {this.code});

  @override
  String toString() => 'AuthException: $message';
}

class UsernameNotifier extends Notifier<String?> {
  @override
  String? build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return prefs.getString('auth_username');
  }

  @override
  set state(String? value) => super.state = value;
}

final usernameProvider =
    NotifierProvider<UsernameNotifier, String?>(UsernameNotifier.new);

class AuthSession {
  final int? userId;
  final String username;
  final String token;
  final String role;
  final String userImage;
  final String? displayName;

  AuthSession({
    this.userId,
    required this.username,
    required this.token,
    required this.role,
    required this.userImage,
    this.displayName,
  });

  Map<String, dynamic> toJson() => {
        if (userId != null) 'userId': userId,
        'username': username,
        'token': token,
        'role': role,
        'userImage': userImage,
        if (displayName != null) 'displayName': displayName,
      };

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final rawId = json['userId'];
    final parsedId = rawId is int ? rawId : int.tryParse('$rawId');
    return AuthSession(
      userId: parsedId,
      username: json['username']?.toString() ?? '',
      token: json['token']?.toString() ?? '',
      role: json['role']?.toString() ?? 'user',
      userImage: json['userImage']?.toString() ?? '',
      displayName: json['displayName']?.toString(),
    );
  }
}

class AuthService {
  static final AuthService _instance = AuthService._internal();

  factory AuthService() => _instance;

  AuthService._internal();

  static const String _usersKey = 'local_users_db';

  String? _token;
  String? _role;
  String? _username;
  bool _isLoadingSocial = false;
  List<AuthSession> _sessions = [];

  bool get isAuthenticated => (_token ?? '').trim().isNotEmpty;
  bool get isAdmin => isAuthenticated && _role == 'admin';
  bool get isUser => isAuthenticated && _role == 'user';
  bool get isLoadingSocial => _isLoadingSocial;
  String? get role => _role;
  String? get token => _token;
  String? get username => _username;
  List<AuthSession> get sessions {
    _sanitizeSessions();
    return List.unmodifiable(_sessions);
  }

  static String _defaultAvatarUrl(String name) =>
      'https://ui-avatars.com/api/?name=${Uri.encodeComponent(name)}&background=random';

  static bool _hasRealProfileImage(String url) {
    final trimmed = url.trim();
    return trimmed.isNotEmpty && !trimmed.contains('ui-avatars.com');
  }

  void _sanitizeSessions() {
    final byKey = <String, AuthSession>{};
    for (final session in _sessions) {
      final token = session.token.trim();
      final username = session.username.trim();
      if (token.isEmpty || username.isEmpty) continue;

      final key = session.userId != null && session.userId! > 0
          ? 'id:${session.userId}'
          : 'user:${username.toLowerCase()}';
      final existing = byKey[key];
      if (existing == null) {
        byKey[key] = session;
        continue;
      }
      byKey[key] = _pickPreferredSession(existing, session);
    }
    _sessions = byKey.values.toList();
  }

  AuthSession _pickPreferredSession(AuthSession a, AuthSession b) {
    if (_hasRealProfileImage(b.userImage) &&
        !_hasRealProfileImage(a.userImage)) {
      return b;
    }
    if (_hasRealProfileImage(a.userImage) &&
        !_hasRealProfileImage(b.userImage)) {
      return a;
    }
    final current = _username?.trim().toLowerCase();
    if (a.username.trim().toLowerCase() == current) return a;
    if (b.username.trim().toLowerCase() == current) return b;
    if (b.username.trim().length > a.username.trim().length) return b;
    return a;
  }

  Future<void> _persistSessions() async {
    _sanitizeSessions();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'auth_sessions',
      json.encode(_sessions.map((s) => s.toJson()).toList()),
    );
  }

  Future<void> _upsertSession({
    required String username,
    required String token,
    required String role,
    required String userImage,
    int? userId,
    String? displayName,
  }) async {
    final normalizedUser = username.trim();
    final normalizedToken = token.trim();
    if (normalizedUser.isEmpty || normalizedToken.isEmpty) return;

    final session = AuthSession(
      userId: userId,
      username: normalizedUser,
      token: normalizedToken,
      role: role.trim().isEmpty ? 'user' : role.trim(),
      userImage: userImage.trim().isNotEmpty
          ? userImage.trim()
          : _defaultAvatarUrl(normalizedUser),
      displayName:
          displayName?.trim().isNotEmpty == true ? displayName!.trim() : null,
    );

    _sessions.removeWhere((s) {
      if (s.token.trim() == normalizedToken) return true;
      if (userId != null &&
          userId > 0 &&
          s.userId != null &&
          s.userId == userId) {
        return true;
      }
      if (s.username.trim().toLowerCase() == normalizedUser.toLowerCase()) {
        return true;
      }
      return false;
    });
    _sessions.add(session);
    await _persistSessions();
  }

  /// Actualiza la sesión guardada con la foto y el @username reales del API.
  Future<void> syncSessionFromProfile(UserProfile profile) async {
    final token = _token?.trim() ?? '';
    if (token.isEmpty) return;

    final username = profile.username.trim();
    if (username.isEmpty) return;

    await _upsertSession(
      username: username,
      token: token,
      role: (_role ?? 'user').trim(),
      userImage: profile.userImage,
      userId: profile.id,
      displayName: profile.displayName,
    );

    if (_username != null &&
        _username!.trim().toLowerCase() != username.toLowerCase()) {
      _username = username;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_username', username);
    }
  }

  /// Alinea usuario/rol con el JWT real (evita mostrar otro @username guardado en prefs).
  Future<bool> reconcileSessionWithToken() async {
    final token = _token?.trim() ?? '';
    if (token.isEmpty || token.startsWith('token_local_')) return false;

    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/me');
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json; charset=UTF-8',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return false;

      final data = json.decode(response.body) as Map<String, dynamic>;
      final apiUsername = data['username']?.toString().trim() ?? '';
      if (apiUsername.isEmpty) return false;

      final userId = _parseUserId(data['id']);
      final role = data['role']?.toString().trim();
      final displayName = data['name']?.toString();
      final imagePath = data['imagePath']?.toString();

      _username = apiUsername;
      if (role != null && role.isNotEmpty) {
        _role = role;
      }

      await _updateSocialProfile(
        apiUsername,
        persist: true,
        userId: userId,
        displayName: displayName,
        userImage: imagePath,
      );
      return true;
    } catch (e) {
      debugPrint('AuthService -> reconcileSessionWithToken: $e');
      return false;
    }
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final storedToken = prefs.getString('auth_token')?.trim();
    final storedUsername = prefs.getString('auth_username')?.trim();
    final storedRole = prefs.getString('auth_role')?.trim();

    _token = (storedToken == null || storedToken.isEmpty) ? null : storedToken;
    _username = (storedUsername == null || storedUsername.isEmpty)
        ? null
        : storedUsername;
    _role = (storedRole == null || storedRole.isEmpty) ? null : storedRole;

    final sessionsJson = prefs.getString('auth_sessions');
    if (sessionsJson != null) {
      final List<dynamic> decoded = json.decode(sessionsJson);
      _sessions = decoded.map((s) => AuthSession.fromJson(s)).toList();
      _sanitizeSessions();
    }

    _pruneInvalidSessions();

    if (!isAuthenticated) {
      if (_username != null) {
        _username = null;
        _role = null;
        await prefs.remove('auth_username');
        await prefs.remove('auth_role');
      }
      SocialState().onLogout();
      return;
    }

    final hasRealToken = !(_token!.startsWith('token_local_'));
    if (hasRealToken) {
      final reconciled = await reconcileSessionWithToken();
      if (!reconciled && _username != null) {
        await _updateSocialProfile(_username!, persist: false);
      }
    } else if (_username != null) {
      await _updateSocialProfile(_username!, persist: false);
    }

    if (_username != null && hasRealToken) {
      await SocialState().syncCurrentUser();
      await syncSessionFromProfile(SocialState().currentUser);
      await SocialState().syncFollowing(_username!);
    }
  }

  void _pruneInvalidSessions() {
    _sessions.removeWhere((s) => s.token.trim().isEmpty);
    _sanitizeSessions();
  }

  Future<void> pruneSavedSessions() async {
    _pruneInvalidSessions();
    await _persistSessions();
  }

  Future<void> removeSavedSession(String username) async {
    await removeAccount(username);
  }

  Future<void> _updateSocialProfile(
    String user, {
    bool persist = true,
    int? userId,
    String? userImage,
    String? displayName,
  }) async {
    final safeName = user.trim().isEmpty ? 'User' : user.trim();
    final resolvedImage = userImage?.trim().isNotEmpty == true
        ? userImage!.trim()
        : _defaultAvatarUrl(safeName);

    if (persist) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_username', safeName);
      final normalizedToken = _token?.trim() ?? '';
      if (normalizedToken.isEmpty) {
        await prefs.remove('auth_token');
        await prefs.remove('auth_role');
      } else {
        await prefs.setString('auth_token', normalizedToken);
        await prefs.setString('auth_role', (_role ?? 'user').trim());
        await _upsertSession(
          username: safeName,
          token: normalizedToken,
          role: (_role ?? 'user').trim(),
          userImage: resolvedImage,
          userId: userId,
          displayName: displayName,
        );
      }
    }

    SocialState().setCurrentUser(
      UserProfile(
        username: safeName,
        displayName:
            displayName ?? ((safeName == 'admin') ? 'Administrador' : safeName),
        userImage: resolvedImage,
        bio: (safeName == 'admin')
            ? 'Cuenta de administración del sistema.'
            : 'Hola. Acabo de unirme a FitConnect.',
        sport: 'Por definir',
        followers: 0,
        following: 0,
        posts: 0,
        id: userId,
      ),
    );

    if (_token != null && !(_token!.startsWith('token_local_'))) {
      await SocialState().syncCurrentUser();
      await syncSessionFromProfile(SocialState().currentUser);
      await SocialState().syncPosts();
      await SocialState().syncStories();
    }
  }

  int? _parseUserId(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value');
  }

  Future<void> switchAccount(String username) async {
    _sanitizeSessions();
    final normalized = username.trim().toLowerCase();
    final sessionIndex = _sessions.indexWhere(
      (s) => s.username.trim().toLowerCase() == normalized,
    );
    if (sessionIndex == -1) {
      throw AuthException('Cuenta no encontrada en este dispositivo');
    }

    final session = _sessions[sessionIndex];
    _token = session.token;
    _username = session.username;
    _role = session.role;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_username', _username!);
    await prefs.setString('auth_token', _token!);
    await prefs.setString('auth_role', _role!);

    // Re-init social state for new user
    SocialState().onLogout();
    await _updateSocialProfile(
      _username!,
      persist: false,
      userId: session.userId,
      userImage: session.userImage,
      displayName: session.displayName,
    );
    await SocialState().syncCurrentUser();
    await syncSessionFromProfile(SocialState().currentUser);
    await SocialState().syncPosts();
    await SocialState().syncFollowing(_username!);
  }

  Future<void> removeAccount(String username) async {
    final normalized = username.trim().toLowerCase();
    int? userId;
    for (final session in _sessions) {
      if (session.username.trim().toLowerCase() == normalized) {
        userId = session.userId;
        break;
      }
    }
    _sessions.removeWhere((s) {
      if (s.username.trim().toLowerCase() == normalized) return true;
      if (userId != null && userId > 0 && s.userId == userId) return true;
      return false;
    });
    await _persistSessions();
    if (_username != null && _username!.trim().toLowerCase() == normalized) {
      await signOut(clearSavedSession: false);
    }
  }

  Future<void> signInWithUsernameAndPassword({
    String? username,
    String? email,
    required String password,
  }) async {
    final identifier = username ?? email ?? '';
    if (identifier.isEmpty || password.isEmpty) {
      throw AuthException('Credenciales invalidas');
    }

    try {
      // Intentamos siempre por API para obtener un JWT real
      final url = Uri.parse('${ApiConstants.baseUrl}/login');
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json; charset=UTF-8'},
            body: json.encode({
              'email': email,
              'username': username,
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        final user = responseData['user'] as Map<String, dynamic>?;
        _token = responseData['token'];
        _username = user?['username']?.toString();
        _role = responseData['role'] ?? user?['role'] ?? 'user';

        await _updateSocialProfile(
          _username!,
          userId: _parseUserId(user?['id']),
          displayName: user?['name']?.toString(),
        );
        debugPrint('AuthService -> Login en API exitoso: $_username');
        return;
      }

      final errorData = json.decode(response.body);
      throw AuthException(errorData['error'] ?? 'Error en el inicio de sesion');
    } catch (e) {
      if (e is AuthException) rethrow;
      debugPrint('AuthService -> API no disponible: $e');

      final prefs = await SharedPreferences.getInstance();
      final usersJson = prefs.getString(_usersKey);
      final Map<String, dynamic> users =
          usersJson != null ? json.decode(usersJson) : <String, dynamic>{};

      if (users.containsKey(identifier) && users[identifier] == password) {
        _token = 'token_local_${DateTime.now().millisecondsSinceEpoch}';
        _role = 'user';
        _username = identifier;
        _updateSocialProfile(identifier);
        debugPrint(
          'AuthService -> Login local (fallback) exitoso: $identifier',
        );
        return;
      }
    }

    throw AuthException(
      'Servidor no disponible en este momento. Intentalo de nuevo en unos segundos.',
      code: 'API_UNAVAILABLE',
    );
  }

  Future<void> register({
    required String email,
    required String username,
    required String password,
    required String gender,
    String? name,
  }) async {
    if (email.isEmpty ||
        username.isEmpty ||
        password.isEmpty ||
        gender.isEmpty) {
      throw AuthException('Rellena todos los campos');
    }

    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/register');
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json; charset=UTF-8'},
            body: json.encode({
              'email': email,
              'username': username,
              'password': password,
              'gender': gender,
              'name': (name ?? '').trim().isEmpty ? username : name,
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 201) {
        final responseData = json.decode(response.body);
        final user = responseData['user'] as Map<String, dynamic>?;
        _token = responseData['token'];
        _username = user?['username']?.toString() ?? username;
        _role = responseData['role'] ?? user?['role'] ?? 'user';

        debugPrint('AuthService -> Registro en API exitoso: $username');
        await _saveLocalUser(username, password);
        await _updateSocialProfile(
          _username!,
          userId: _parseUserId(user?['id']),
          displayName: user?['name']?.toString(),
        );
        return;
      }

      final errorData = json.decode(response.body) as Map<String, dynamic>;
      throw AuthException(
        errorData['error']?.toString() ?? 'Error al registrar el usuario',
        code: errorData['code']?.toString(),
      );
    } catch (e) {
      if (e is AuthException) rethrow;
      debugPrint(
        'AuthService -> Error conectando con la API para registro: $e',
      );
      throw AuthException(
        'No se ha podido conectar con el servidor para guardar los datos.',
      );
    }
  }

  Future<String> forgotPassword({required String email}) async {
    final normalizedEmail = email.trim();
    if (normalizedEmail.isEmpty) {
      throw AuthException('Introduce tu correo electronico');
    }

    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/forgot-password');
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json; charset=UTF-8'},
            body: json.encode({'email': normalizedEmail}),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final responseData = _tryDecodeJson(response.body);
        return responseData['delivery'] ?? 'email';
      }

      final errorData = _tryDecodeJson(response.body);
      throw AuthException(
        errorData['error']?.toString() ??
            'No se pudo enviar el correo de recuperacion',
        code: errorData['code']?.toString(),
      );
    } catch (e) {
      if (e is AuthException) rethrow;
      debugPrint(
        'AuthService -> Error conectando con la API para recuperar contrasena: $e',
      );
      throw AuthException(
        'No se ha podido conectar con el servidor para recuperar la contrasena. Intenta de nuevo en unos segundos.',
      );
    }
  }

  Future<void> resetPassword({
    required String token,
    required String password,
  }) async {
    final normalizedToken = token.trim();
    final normalizedPassword = password.trim();

    if (normalizedToken.isEmpty || normalizedPassword.isEmpty) {
      throw AuthException('Token y contrasena son obligatorios');
    }

    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/reset-password');
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json; charset=UTF-8'},
            body: json.encode({
              'token': normalizedToken,
              'password': normalizedPassword,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        return;
      }

      final errorData = _tryDecodeJson(response.body);
      throw AuthException(
        errorData['error'] ?? 'No se pudo actualizar la contrasena',
      );
    } catch (e) {
      if (e is AuthException) rethrow;
      debugPrint(
        'AuthService -> Error conectando con la API para reset-password: $e',
      );
      throw AuthException(
        'No se ha podido conectar con el servidor para actualizar la contrasena.',
      );
    }
  }

  Map<String, dynamic> _tryDecodeJson(String rawBody) {
    try {
      final decoded = json.decode(rawBody);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {}
    return <String, dynamic>{};
  }

  void _applySessionFromOAuthResponse(Map<String, dynamic> responseData) {
    final user = responseData['user'] as Map<String, dynamic>?;
    _token = responseData['token'] as String?;
    _username = user?['username'] as String?;
    _role = (responseData['role'] as String?) ?? 'user';
    if (_username != null && _username!.isNotEmpty) {
      _updateSocialProfile(
        _username!,
        userId: _parseUserId(user?['id']),
        displayName: user?['name']?.toString(),
      );
    }
  }

  /// Devuelve [true] si la cuenta se acaba de crear (mostrar onboarding).
  Future<bool> signInWithGoogle() async {
    _isLoadingSocial = true;
    try {
      final cid = OauthConfig.googleWebClientId.trim();
      if (cid.isEmpty) {
        throw AuthException(
          'Define GOOGLE_WEB_CLIENT_ID al ejecutar la app (cliente OAuth tipo Web de Google Cloud).',
        );
      }

      final google = GoogleSignIn(
        scopes: const ['email', 'profile'],
        clientId: kIsWeb ? cid : null,
        serverClientId: cid,
      );

      final account = await google.signIn();
      if (account == null) {
        throw AuthException('Inicio de sesion con Google cancelado');
      }

      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw AuthException(
          'Google no devolvio idToken. En Android, anade el SHA-1 en Google Cloud y usa el ID de cliente Web en GOOGLE_WEB_CLIENT_ID.',
        );
      }

      final url = Uri.parse('${ApiConstants.baseUrl}/oauth/google');
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json; charset=UTF-8'},
            body: json.encode({'idToken': idToken}),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        _applySessionFromOAuthResponse(data);
        debugPrint('AuthService -> Google OAuth: $_username');
        return data['isNewUser'] == true;
      }

      final err = _tryDecodeError(response.body);
      throw AuthException(err ?? 'Error al iniciar sesion con Google');
    } on AuthException {
      rethrow;
    } catch (e) {
      debugPrint('AuthService -> Google OAuth error: $e');
      throw AuthException('No se pudo completar el inicio con Google.');
    } finally {
      _isLoadingSocial = false;
    }
  }

  /// Devuelve [true] si la cuenta se acaba de crear.
  Future<bool> signInWithApple() async {
    if (kIsWeb) {
      throw AuthException(
        'Sign in with Apple en web requiere configuracion adicional; usa iOS o macOS.',
      );
    }
    if (defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.macOS) {
      throw AuthException(
        'Sign in with Apple solo esta disponible en iPhone, iPad o Mac.',
      );
    }

    _isLoadingSocial = true;
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final token = credential.identityToken;
      if (token == null || token.isEmpty) {
        throw AuthException('Apple no devolvio identity token');
      }

      final url = Uri.parse('${ApiConstants.baseUrl}/oauth/apple');
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json; charset=UTF-8'},
            body: json.encode({
              'identityToken': token,
              if (credential.email != null && credential.email!.isNotEmpty)
                'emailHint': credential.email,
              if (credential.givenName != null &&
                  credential.givenName!.isNotEmpty)
                'givenName': credential.givenName,
              if (credential.familyName != null &&
                  credential.familyName!.isNotEmpty)
                'familyName': credential.familyName,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        _applySessionFromOAuthResponse(data);
        debugPrint('AuthService -> Apple OAuth: $_username');
        return data['isNewUser'] == true;
      }

      final err = _tryDecodeError(response.body);
      throw AuthException(err ?? 'Error al iniciar sesion con Apple');
    } on AuthException {
      rethrow;
    } catch (e) {
      debugPrint('AuthService -> Apple OAuth error: $e');
      throw AuthException('No se pudo completar el inicio con Apple.');
    } finally {
      _isLoadingSocial = false;
    }
  }

  String? _tryDecodeError(String body) {
    try {
      final m = json.decode(body);
      if (m is Map && m['error'] is String) return m['error'] as String;
    } catch (_) {}
    return null;
  }

  Future<void> signOut({bool clearSavedSession = true}) async {
    final loggingOutUser = _username?.trim();
    final prefs = await SharedPreferences.getInstance();
    if (loggingOutUser != null && loggingOutUser.isNotEmpty) {
      await prefs.setString(AppThemeNotifier.lastThemeUserKey, loggingOutUser);
    }

    int? loggingOutUserId;
    if (clearSavedSession && loggingOutUser != null) {
      final normalized = loggingOutUser.toLowerCase();
      for (final session in _sessions) {
        if (session.username.trim().toLowerCase() == normalized) {
          loggingOutUserId = session.userId;
          break;
        }
      }
    }

    try {
      final cid = OauthConfig.googleWebClientId;
      if (cid.isNotEmpty) {
        await GoogleSignIn(
          scopes: const ['email', 'profile'],
          serverClientId: cid,
        ).signOut();
      }
    } catch (_) {}

    _token = null;
    _role = null;
    _username = null;
    await prefs.remove('auth_token');
    await prefs.remove('auth_username');
    await prefs.remove('auth_role');

    if (clearSavedSession &&
        loggingOutUser != null &&
        loggingOutUser.isNotEmpty) {
      _sessions.removeWhere((s) {
        if (s.username.trim().toLowerCase() == loggingOutUser.toLowerCase()) {
          return true;
        }
        if (loggingOutUserId != null &&
            loggingOutUserId > 0 &&
            s.userId == loggingOutUserId) {
          return true;
        }
        return false;
      });
      await _persistSessions();
    }

    ChatRealtimeService.instance.disconnect();
    SocialState().onLogout();
    debugPrint('AuthService -> Sesion cerrada.');
  }

  /// Elimina todas las cuentas guardadas en el dispositivo (p. ej. tras limpiar datos).
  Future<void> clearAllSavedSessions() async {
    _sessions.clear();
    await _persistSessions();
  }

  Future<void> _saveLocalUser(String username, String password) async {
    final prefs = await SharedPreferences.getInstance();
    final usersJson = prefs.getString(_usersKey);
    final Map<String, dynamic> users =
        usersJson != null ? json.decode(usersJson) : <String, dynamic>{};

    users[username] = password;
    await prefs.setString(_usersKey, json.encode(users));
  }
}
