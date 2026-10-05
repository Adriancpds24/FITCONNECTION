import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/assets.dart';
import '../../core/theme/theme_provider.dart';
import '../auth/auth_service.dart';
import '../auth/password_policy.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final AuthService _authService = AuthService();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final LocalAuthentication _localAuth = LocalAuthentication();

  bool _isLoading = false;
  bool _isLogin = true;
  bool _hasSavedCredentials = false;
  String? _selectedGender;

  static const _keyBiometricOffered = 'biometric_setup_offered';
  static const _keyBiometricEnabled = 'biometric_login_enabled';
  static const _legacyUsernameKey = 'biometric_username';
  static const _legacyPasswordKey = 'biometric_password';

  /// iOS: llavero del sistema + Face ID al autocompletar. Android: huella en la app.
  bool get _useInAppBiometric =>
      !kIsWeb &&
      defaultTargetPlatform != TargetPlatform.iOS &&
      defaultTargetPlatform != TargetPlatform.macOS;

  static const Map<String, String> _genderLabels = {
    'hombre': 'Hombre',
    'mujer': 'Mujer',
    'otro': 'Otro',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkSavedUserForBiometrics();
      if (AuthService().isAuthenticated) {
        if (!mounted) return;
        final prefs = await SharedPreferences.getInstance();
        final hasSeen = prefs.getBool('hasSeenOnboarding') ?? false;
        if (!mounted) return;
        Navigator.pushReplacementNamed(
          context,
          hasSeen ? '/home' : '/onboarding',
        );
        return;
      }
      await AuthService().pruneSavedSessions();
      if (!mounted || _isLoading) return;
      if (_useInAppBiometric) {
        await _tryAutoBiometricLogin();
      }
    });
  }

  Future<void> _migrateLegacyCredentials() async {
    final legacyUser = await _secureStorage.read(key: _legacyUsernameKey);
    final legacyPass = await _secureStorage.read(key: _legacyPasswordKey);
    if (legacyUser == null) return;

    final currentUser = await _secureStorage.read(key: 'username');
    if (currentUser == null) {
      await _secureStorage.write(key: 'username', value: legacyUser);
    }
    if (legacyPass != null) {
      final currentPass = await _secureStorage.read(key: 'password');
      if (currentPass == null) {
        await _secureStorage.write(key: 'password', value: legacyPass);
      }
    }
    await _secureStorage.delete(key: _legacyUsernameKey);
    await _secureStorage.delete(key: _legacyPasswordKey);
  }

  Future<void> _checkSavedUserForBiometrics() async {
    if (kIsWeb) return;

    try {
      await _migrateLegacyCredentials();
      final savedUser = await _secureStorage.read(key: 'username');
      final savedPass = await _secureStorage.read(key: 'password');
      final canCheck = await _localAuth.canCheckBiometrics;
      final enabled =
          await _secureStorage.read(key: _keyBiometricEnabled) == 'true';

      if (savedUser != null && mounted) {
        setState(() {
          _userController.text = savedUser;
          if (savedPass != null && canCheck && enabled) {
            _hasSavedCredentials = true;
          }
        });
      }
    } catch (e) {
      debugPrint('Error checking saved user: $e');
    }
  }

  Future<String> _biometricDisplayName() async {
    if (kIsWeb) return 'biometría';
    try {
      final types = await _localAuth.getAvailableBiometrics();
      if (types.contains(BiometricType.face)) return 'Face ID';
      if (types.contains(BiometricType.fingerprint)) {
        return defaultTargetPlatform == TargetPlatform.iOS
            ? 'Touch ID'
            : 'huella dactilar';
      }
    } catch (_) {}
    return 'biometría';
  }

  Future<void> _offerBiometricSetupIfNeeded() async {
    if (kIsWeb || !_useInAppBiometric || !mounted) return;

    final canCheck = await _localAuth.canCheckBiometrics;
    final supported = await _localAuth.isDeviceSupported();
    if (!canCheck || !supported) return;

    final offered = await _secureStorage.read(key: _keyBiometricOffered);
    if (offered == 'true') return;

    await _secureStorage.write(key: _keyBiometricOffered, value: 'true');
    final biometricName = await _biometricDisplayName();
    if (!mounted) return;

    final enable = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final accent = ref.read(themeProvider).accent;
        return AlertDialog(
          backgroundColor: const Color(0xFF151515),
          title: Text(
            'Inicio rápido',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Text(
            'Usa $biometricName para entrar sin escribir la contraseña cada vez.',
            style: GoogleFonts.outfit(color: Colors.grey.shade400),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Ahora no'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: accent),
              child: const Text('Activar'),
            ),
          ],
        );
      },
    );

    if (enable != true || !mounted) return;

    try {
      final ok = await _localAuth.authenticate(
        localizedReason: 'Accede a FitConnect de forma segura',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      if (ok) {
        await _secureStorage.write(key: _keyBiometricEnabled, value: 'true');
        if (mounted) {
          setState(() => _hasSavedCredentials = true);
        }
      }
    } catch (e) {
      debugPrint('Biometric setup: $e');
    }
  }

  Future<void> _tryAutoBiometricLogin() async {
    if (kIsWeb || _isLoading || !_hasSavedCredentials || !_isLogin) return;
    final enabled =
        await _secureStorage.read(key: _keyBiometricEnabled) == 'true';
    if (!enabled) return;
    await _authenticateAndLogin();
  }

  Future<void> _authenticateAndLogin() async {
    try {
      final savedUser = await _secureStorage.read(key: 'username');
      final savedPass = await _secureStorage.read(key: 'password');

      if (savedUser != null && savedPass != null) {
        final didAuthenticate = await _localAuth.authenticate(
          localizedReason: 'Accede a FitConnect de forma segura',
          biometricOnly: true,
          persistAcrossBackgrounding: true,
        );

        if (didAuthenticate && mounted) {
          _userController.text = savedUser;
          _passwordController.text = savedPass;
          await _loginWithCredentials(
            username: savedUser,
            password: savedPass,
            fromBiometric: true,
          );
        }
      }
    } catch (e) {
      debugPrint('Error en autenticación biométrica: $e');
    }
  }

  Future<void> _persistLoginSecrets({
    required String username,
    required String password,
  }) async {
    if (kIsWeb) return;

    await _secureStorage.write(key: 'username', value: username);
    if (_useInAppBiometric) {
      await _secureStorage.write(key: 'password', value: password);
    }
  }

  Future<void> _handleSubmit() async {
    if (_isLoading) return;

    final displayName = _nameController.text.trim();
    final username = _userController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final gender = _selectedGender;

    if (username.isEmpty || (!_isLogin && email.isEmpty) || password.isEmpty) {
      _showError('Por favor, rellena todos los campos');
      return;
    }

    if (!_isLogin && displayName.isEmpty) {
      _showError('Introduce tu nombre');
      return;
    }

    if (!_isLogin && gender == null) {
      _showError('Selecciona tu sexo');
      return;
    }

    if (_isLogin) {
      await _loginWithCredentials(username: username, password: password);
      return;
    }

    if (!_isLogin) {
      final strengthError = validateStrongPassword(password);
      if (strengthError != null) {
        _showError(strengthError);
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      await _authService.register(
        email: email,
        username: username,
        password: password,
        gender: gender!,
        name: displayName,
      );

      if (mounted) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('hasSeenOnboarding', false);

        await _persistLoginSecrets(username: username, password: password);
        TextInput.finishAutofillContext(shouldSave: true);

        if (!mounted) return;
        ref.read(usernameProvider.notifier).state = username;
        ref.read(themeProvider.notifier).refreshForUser();
        Navigator.pushReplacementNamed(context, '/onboarding');
      }
    } on AuthException catch (e) {
      if (e.code == 'USERNAME_EXISTS') {
        _showCenteredMessage(
          'Usuario no disponible',
          'Ese nombre de usuario ya existe. Prueba con otro.',
        );
      } else if (e.code == 'EMAIL_EXISTS') {
        _showCenteredMessage(
          'Correo en uso',
          'Ya hay una cuenta registrada con ese correo.',
        );
      } else {
        _showCenteredMessage('No se pudo crear la cuenta', e.message);
      }
    } catch (e) {
      _showError('Error inesperado: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loginWithCredentials({
    required String username,
    required String password,
    bool fromBiometric = false,
  }) async {
    if (_isLoading) return;

    final normalizedUsername = username.trim();
    final normalizedPassword = password.trim();

    if (normalizedUsername.isEmpty || normalizedPassword.isEmpty) {
      _showError('Por favor, rellena todos los campos');
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _authService.signInWithUsernameAndPassword(
        username: normalizedUsername,
        password: normalizedPassword,
      );

      await _persistLoginSecrets(
        username: normalizedUsername,
        password: normalizedPassword,
      );
      TextInput.finishAutofillContext(shouldSave: true);

      if (!mounted) return;
      await _offerBiometricSetupIfNeeded();
      if (!mounted) return;

      final prefs = await SharedPreferences.getInstance();
      final hasSeen = prefs.getBool('hasSeenOnboarding') ?? false;

      if (!mounted) return;

      ref.read(usernameProvider.notifier).state = normalizedUsername;
      ref.read(themeProvider.notifier).refreshForUser();

      if (!hasSeen) {
        Navigator.pushReplacementNamed(context, '/onboarding');
      } else {
        Navigator.pushReplacementNamed(context, '/home');
      }
    } on AuthException catch (e) {
      if (fromBiometric) {
        await _secureStorage.delete(key: 'password');
        await _secureStorage.delete(key: _keyBiometricEnabled);
        if (mounted) {
          setState(() => _hasSavedCredentials = false);
        }
        _showError(
          'Las credenciales guardadas ya no son válidas. Inicia sesión manualmente.',
        );
      } else {
        _showError(e.message);
      }
    } catch (e) {
      _showError('Error inesperado: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleForgotPassword() async {
    final emailController = TextEditingController(
      text: _emailController.text.trim(),
    );
    final theme = ref.read(themeProvider);

    try {
      final email = await showDialog<String>(
        context: context,
        barrierDismissible: !_isLoading,
        builder: (dialogContext) {
          return AlertDialog(
            backgroundColor: const Color(0xFF111111),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              'Recuperar contraseña',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Introduce tu correo y te enviaremos el enlace para restablecerla.',
                  style: GoogleFonts.outfit(
                    color: Colors.grey.shade400,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: emailController,
                  hint: 'Correo electronico',
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text(
                  'Cancelar',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(
                  dialogContext,
                ).pop(emailController.text.trim()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.accent,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Enviar correo'),
              ),
            ],
          );
        },
      );

      if (!mounted || email == null || email.isEmpty) {
        return;
      }

      setState(() => _isLoading = true);
      await _authService.forgotPassword(email: email);
      if (mounted) {
        _showCenteredMessage(
          'Correo enviado',
          'Si el correo existe en FitConnect, recibirás instrucciones para restablecer tu contraseña.',
          isSuccess: true,
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        if (e.code == 'EMAIL_NOT_FOUND') {
          _showCenteredMessage('Correo no registrado', e.message);
        } else {
          _showCenteredMessage('No se pudo enviar', e.message);
        }
      }
    } catch (e) {
      if (mounted) {
        _showCenteredMessage('Error', 'Error inesperado: $e');
      }
    } finally {
      emailController.dispose();
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showCenteredMessage(
    String title,
    String message, {
    bool isSuccess = false,
  }) {
    final theme = ref.read(themeProvider);

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 320,
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
              decoration: BoxDecoration(
                color: const Color(0xFF151515),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: isSuccess
                      ? Colors.green.withValues(alpha: 0.45)
                      : Colors.redAccent.withValues(alpha: 0.45),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isSuccess ? Icons.check_circle_outline : Icons.info_outline,
                    color: isSuccess ? Colors.greenAccent : Colors.redAccent,
                    size: 40,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      color: Colors.grey.shade400,
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            isSuccess ? Colors.green : theme.accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Entendido'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final horizontalPadding = screenWidth < 360 ? 24.0 : 32.0;
    final logoWidth = (screenWidth * 0.78).clamp(220.0, 360.0).toDouble();
    final titleFontSize = screenWidth < 360 ? 32.0 : 38.0;
    final theme = ref.watch(themeProvider);
    final accent = theme.accent;
    final backgroundStart = Color.lerp(const Color(0xFF111111), accent, 0.10)!;

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [backgroundStart, const Color(0xFF000000)],
              ),
            ),
          ),
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withAlpha(26),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: AutofillGroup(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Hero(
                        tag: 'logo',
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            boxShadow: [
                              BoxShadow(
                                color: accent.withAlpha(77),
                                blurRadius: 40,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: Image.asset(
                            AppAssets.logo,
                            width: logoWidth,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Fitconnect',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Evoluciona tu potencial',
                        style: GoogleFonts.outfit(
                          color: Colors.grey.shade500,
                          fontSize: 16,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 60),
                      _buildTextField(
                        controller: _userController,
                        hint: 'Usuario',
                        icon: Icons.person_outline_rounded,
                        autofillHints: const [AutofillHints.username],
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 16),
                      if (!_isLogin) ...[
                        _buildTextField(
                          controller: _nameController,
                          hint: 'Nombre',
                          icon: Icons.badge_outlined,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _emailController,
                          hint: 'Correo electronico',
                          icon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 16),
                        _buildGenderSelector(),
                        const SizedBox(height: 16),
                      ],
                      _buildTextField(
                        controller: _passwordController,
                        hint: 'Contraseña',
                        icon: Icons.lock_outline_rounded,
                        isPassword: true,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _handleSubmit(),
                        showBiometricAction: _isLogin &&
                            _useInAppBiometric &&
                            _hasSavedCredentials,
                        onBiometricTap: _authenticateAndLogin,
                      ),
                      if (_isLogin) ...[
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed:
                                _isLoading ? null : _handleForgotPassword,
                            child: Text(
                              'Has olvidado la contraseña?',
                              style: GoogleFonts.outfit(
                                color: accent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 40),
                      SizedBox(
                        width: double.infinity,
                        height: 60,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _handleSubmit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                            elevation: 8,
                            shadowColor: accent.withValues(
                              alpha: 0.4,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: _isLoading
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              : Text(
                                  _isLogin ? 'INICIAR SESION' : 'CREAR CUENTA',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextButton(
                        onPressed: () {
                          setState(() => _isLogin = !_isLogin);
                        },
                        child: RichText(
                          text: TextSpan(
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 14,
                            ),
                            children: [
                              TextSpan(
                                text: _isLogin
                                    ? 'No tienes cuenta? '
                                    : 'Ya tienes cuenta? ',
                              ),
                              TextSpan(
                                text: _isLogin
                                    ? 'Registrate aqui'
                                    : 'Inicia sesion',
                                style: TextStyle(
                                  color: accent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    TextInputType? keyboardType,
    Iterable<String>? autofillHints,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
    bool showBiometricAction = false,
    VoidCallback? onBiometricTap,
  }) {
    final accent = ref.read(themeProvider).accent;
    const fieldFill = Color(0xFF1A1F1C);
    const fieldBorder = Color(0xFF2A332E);

    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      decoration: BoxDecoration(
        color: fieldFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: fieldBorder),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword,
        keyboardType: keyboardType,
        autofillHints: autofillHints,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        style: const TextStyle(color: Colors.white, fontSize: 16),
        cursorColor: accent,
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.transparent,
          prefixIcon: Icon(icon, color: accent, size: 22),
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade500),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 18,
          ),
          suffixIcon: showBiometricAction
              ? IconButton(
                  icon: Icon(Icons.fingerprint_rounded, color: accent),
                  onPressed: _isLoading ? null : onBiometricTap,
                  tooltip: 'Autocompletar con biometría',
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildGenderSelector() {
    final accent = ref.read(themeProvider).accent;

    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F1C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A332E)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            Icon(Icons.wc_rounded, color: accent, size: 22),
            const SizedBox(width: 16),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedGender,
                  isExpanded: true,
                  dropdownColor: Colors.grey.shade900,
                  borderRadius: BorderRadius.circular(16),
                  icon: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: accent,
                  ),
                  hint: Text(
                    'Sexo',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  items: _genderLabels.entries
                      .map(
                        (entry) => DropdownMenuItem<String>(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                      )
                      .toList(),
                  onChanged: _isLoading
                      ? null
                      : (value) => setState(() => _selectedGender = value),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _userController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
