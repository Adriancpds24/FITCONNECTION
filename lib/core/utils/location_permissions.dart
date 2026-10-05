import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Solicita permiso de ubicación cuando la app lo necesite (p. ej. mapa).
Future<bool> ensureLocationPermission() async {
  if (kIsWeb) return true;

  var status = await Permission.locationWhenInUse.status;
  if (status.isGranted) return true;
  if (status.isPermanentlyDenied) return false;

  status = await Permission.locationWhenInUse.request();
  return status.isGranted;
}
