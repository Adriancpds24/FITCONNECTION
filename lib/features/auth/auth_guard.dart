import 'package:flutter/material.dart';
import 'auth_service.dart';

class AuthGuard extends StatelessWidget {
  final Widget child;

  const AuthGuard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // Verificamos si el usuario está autenticado usando el Singleton
    if (!AuthService().isAuthenticated) {
      // Si no tiene token, lo redirigimos al login inmediatamente
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/login', (route) => false);
      });

      return const Scaffold(
        backgroundColor: Color(0xFF000000),
        body: Center(
          child: CircularProgressIndicator(color: Colors.white54),
        ),
      );
    }

    // Si está autenticado, dejamos pasar y mostramos la pantalla solicitada
    return child;
  }
}
