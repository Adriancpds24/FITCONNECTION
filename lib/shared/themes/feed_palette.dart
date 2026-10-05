import 'package:flutter/material.dart';
import '../../core/theme/theme_provider.dart';

class FeedPalette {
  static AppThemeState _state = AppThemeState.orange();

  static void update(AppThemeState newState) {
    _state = newState;
  }

  static bool get isDark => _state.isDarkMode;

  static Color get background => _state.background;
  static Color get surface => _state.surface;
  static Color get surfaceSoft => _state.surfaceSoft;
  static Color get accent => _state.accent;
  static Color get text => _state.text;
  static Color get muted => _state.muted;
  static Color get border => _state.border;

  static LinearGradient get screenGradient => _state.screenGradient;
  static LinearGradient get heroGradient => _state.heroGradient;
  static LinearGradient get storyGradient => _state.storyGradient;

  /// Fondo para campos de texto y barras de búsqueda.
  static Color get inputFill => surfaceSoft;

  /// Texto sobre tarjetas destacadas (p. ej. conversaciones no leídas en modo claro).
  static Color get onHighlightSurface =>
      isDark ? text : const Color(0xFF1A1A1A);

  /// Superficie para filas o tarjetas con énfasis (no leídas, etc.).
  static Color highlightSurface({bool emphasized = false}) {
    if (!emphasized) return surface;
    return isDark
        ? Color.alphaBlend(accent.withValues(alpha: 0.14), surface)
        : Colors.white;
  }

  static TextStyle get bodyTextStyle => TextStyle(color: text, fontSize: 16);

  static TextStyle get sectionHeaderStyle => TextStyle(
        color: muted,
        fontWeight: FontWeight.bold,
        fontSize: 13,
      );

  /// Campo de búsqueda con contraste correcto en claro y oscuro.
  static InputDecoration searchFieldDecoration({
    String hint = 'Buscar',
    Widget? suffixIcon,
  }) {
    return textFieldDecoration(
      hint: hint,
      prefixIcon: Icon(Icons.search, color: muted, size: 22),
      suffixIcon: suffixIcon,
      radius: 12,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  static Widget searchField({
    TextEditingController? controller,
    String hint = 'Buscar',
    ValueChanged<String>? onChanged,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: bodyTextStyle,
      cursorColor: accent,
      decoration: searchFieldDecoration(hint: hint, suffixIcon: suffixIcon),
    );
  }

  static BoxDecoration panelDecoration({double radius = 28, Color? color}) {
    return BoxDecoration(
      color: color ?? surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: border),
      boxShadow: [
        BoxShadow(
          color: accent.withValues(alpha: 0.12),
          blurRadius: 18,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }

  static BoxDecoration heroDecoration({double radius = 30}) {
    return BoxDecoration(
      gradient: heroGradient,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(
          color: accent.withValues(alpha: 0.2),
          blurRadius: 26,
          offset: const Offset(0, 12),
        ),
      ],
    );
  }

  static ButtonStyle primaryButtonStyle({
    double radius = 20,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
      horizontal: 22,
      vertical: 16,
    ),
  }) {
    return ElevatedButton.styleFrom(
      backgroundColor: accent,
      foregroundColor: Colors.white,
      elevation: 0,
      minimumSize: const Size.fromHeight(54),
      shadowColor: accent.withValues(alpha: 0.3),
      padding: padding,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  static ButtonStyle softButtonStyle({
    double radius = 20,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
      horizontal: 22,
      vertical: 16,
    ),
  }) {
    return ElevatedButton.styleFrom(
      backgroundColor: surface,
      foregroundColor: text,
      elevation: 0,
      minimumSize: const Size.fromHeight(54),
      padding: padding,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: border),
      ),
    );
  }

  static InputDecoration inputDecoration({
    required String hint,
    required IconData icon,
  }) {
    return textFieldDecoration(
      hint: hint,
      prefixIcon: Icon(icon, color: accent, size: 20),
    );
  }

  static InputDecoration textFieldDecoration({
    String? hint,
    Widget? prefixIcon,
    Widget? suffixIcon,
    double radius = 16,
    EdgeInsetsGeometry contentPadding =
        const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: BorderSide(color: FeedPalette.border),
    );
    return InputDecoration(
      hintText: hint,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      hintStyle: TextStyle(color: muted, fontSize: 14),
      filled: true,
      fillColor: inputFill,
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: accent, width: 2),
      ),
      contentPadding: contentPadding,
    );
  }
}
