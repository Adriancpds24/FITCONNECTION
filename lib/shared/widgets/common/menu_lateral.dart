import 'package:flutter/material.dart';
// Importaciones de tus rutas según tu estructura
import '../../../features/home/home.dart';

import '../../../features/auth/auth_service.dart';

class MenuLateral extends StatelessWidget {
  const MenuLateral({super.key});

  @override
  Widget build(BuildContext context) {
    // Detectamos la ruta actual para saber qué opción iluminar
    final String? currentRoute = ModalRoute.of(context)?.settings.name;

    return Drawer(
      width: MediaQuery.of(context).size.width *
          0.60, // Ajustado a 60% para que se lea mejor
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            // Cabecera opcional o espacio superior
            const SizedBox(height: 20),

            // Cuerpo del menú con scroll
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: [
                  _menuTile(
                    context,
                    'Fichaje',
                    Icons.timer,
                    const HomePage(),
                    '/home',
                    currentRoute,
                  ),
                  // Se añadirán las nuevas opciones de FitConnect aquí.
                ],
              ),
            ),

            // Botón de Cerrar Sesión al final
            const Divider(),
            ListTile(
              leading: const Icon(Icons.exit_to_app, color: Colors.red),
              title: const Text(
                'Cerrar Sesión',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onTap: () async {
                if (!context.mounted) return;
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/login',
                  (route) => false,
                );
                await AuthService().signOut();
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  // Widget personalizado para las opciones
  Widget _menuTile(
    BuildContext context,
    String title,
    IconData icon,
    Widget page,
    String routeName,
    String? currentRoute,
  ) {
    // Comprobamos si esta es la página donde está el usuario
    bool isActive = currentRoute == routeName;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        // Si está activo: fondo gris suave. Si no: transparente.
        color:
            isActive ? Colors.grey.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: isActive ? Colors.blue : Colors.black54,
          size: 22,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isActive ? Colors.blue.shade800 : Colors.black87,
            fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
            fontSize: 15,
          ),
        ),
        // Si ya estamos en esa página, no hace nada al pulsar (evita recargas innecesarias)
        onTap: isActive
            ? null
            : () {
                // Usamos navegación por nombre para pasar por el AuthGuard.
                // El menú se cierra automáticamente al reemplazar la ruta.
                Navigator.pushReplacementNamed(context, routeName);
              },
      ),
    );
  }
}
