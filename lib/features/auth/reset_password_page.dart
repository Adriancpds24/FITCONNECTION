import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'auth_service.dart';
import 'password_policy.dart';

class ResetPasswordPage extends StatefulWidget {
  final String? initialToken;

  const ResetPasswordPage({super.key, this.initialToken});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final AuthService _authService = AuthService();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  String _resetToken = '';
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void initState() {
    super.initState();
    final tokenFromUrl = Uri.base.queryParameters['token'];
    _resetToken = (widget.initialToken ?? tokenFromUrl ?? '').trim();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleResetPassword() async {
    if (_isLoading) return;

    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (_resetToken.isEmpty) {
      _showError('Token no válido. Solicita un nuevo correo de recuperación.');
      return;
    }

    if (password.isEmpty || confirmPassword.isEmpty) {
      _showError('Introduce y confirma la nueva contraseña.');
      return;
    }

    final strengthError = validateStrongPassword(password);
    if (strengthError != null) {
      _showError(strengthError);
      return;
    }

    if (password != confirmPassword) {
      _showError('Las contraseñas no coinciden.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _authService.resetPassword(token: _resetToken, password: password);
      TextInput.finishAutofillContext(shouldSave: true);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Contraseña actualizada correctamente.'),
          behavior: SnackBarBehavior.floating,
        ),
      );

      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    } on AuthException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Error inesperado: $e');
    } finally {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final primary = scheme.primary;
    final textColor = scheme.onSurface;
    final mutedText = scheme.onSurface.withValues(alpha: 0.72);
    final panelColor = theme.scaffoldBackgroundColor.withValues(alpha: 0.78);
    final panelBorder = scheme.outline.withValues(alpha: 0.45);
    final fieldColor = scheme.surface.withValues(alpha: 0.92);

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.surface.withValues(alpha: 0.98),
                  scheme.surfaceContainerHighest.withValues(alpha: 0.85),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 460),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: panelColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: panelBorder),
                  ),
                  child: AutofillGroup(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Nueva contraseña',
                          style: GoogleFonts.outfit(
                            color: textColor,
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Introduce tu nueva contraseña para recuperar el acceso.',
                          style: GoogleFonts.outfit(
                            color: mutedText,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _buildField(
                          controller: _passwordController,
                          hint: 'Nueva contraseña',
                          icon: Icons.lock_outline_rounded,
                          isPassword: true,
                          obscureText: _obscurePassword,
                          onToggleObscure: () {
                            setState(
                                () => _obscurePassword = !_obscurePassword);
                          },
                          accentColor: primary,
                          fieldColor: fieldColor,
                          textColor: textColor,
                          mutedText: mutedText,
                          borderColor: panelBorder,
                          autofillHints: const [AutofillHints.newPassword],
                        ),
                        const SizedBox(height: 14),
                        _buildField(
                          controller: _confirmPasswordController,
                          hint: 'Confirmar nueva contraseña',
                          icon: Icons.lock_reset_rounded,
                          isPassword: true,
                          obscureText: _obscureConfirmPassword,
                          onToggleObscure: () {
                            setState(
                              () => _obscureConfirmPassword =
                                  !_obscureConfirmPassword,
                            );
                          },
                          accentColor: primary,
                          fieldColor: fieldColor,
                          textColor: textColor,
                          mutedText: mutedText,
                          borderColor: panelBorder,
                          autofillHints: const [AutofillHints.newPassword],
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleResetPassword,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primary,
                              foregroundColor: scheme.onPrimary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: _isLoading
                                ? const CircularProgressIndicator(
                                    color: Colors.white,
                                  )
                                : SizedBox(
                                    width: double.infinity,
                                    child: Text(
                                      'Guardar nueva contraseña',
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.outfit(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.6,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Center(
                          child: TextButton(
                            onPressed: () {
                              Navigator.pushNamedAndRemoveUntil(
                                context,
                                '/login',
                                (route) => false,
                              );
                            },
                            child: Text(
                              'Volver al login',
                              style: GoogleFonts.outfit(
                                color: primary.withValues(alpha: 0.9),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    bool obscureText = false,
    VoidCallback? onToggleObscure,
    required Color accentColor,
    required Color fieldColor,
    required Color textColor,
    required Color mutedText,
    required Color borderColor,
    Iterable<String>? autofillHints,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: fieldColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword ? obscureText : false,
        autofillHints: autofillHints,
        style: TextStyle(color: textColor),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: accentColor, size: 22),
          suffixIcon: isPassword
              ? IconButton(
                  onPressed: onToggleObscure,
                  icon: Icon(
                    obscureText ? Icons.visibility_off : Icons.visibility,
                    color: mutedText,
                  ),
                )
              : null,
          hintText: hint,
          hintStyle: TextStyle(color: mutedText),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 16,
          ),
        ),
      ),
    );
  }
}
