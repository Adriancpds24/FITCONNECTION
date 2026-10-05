import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

/// Resultado de solicitar permiso de cámara o galería.
enum MediaPermissionStatus {
  granted,
  denied,
  permanentlyDenied,
}

/// Pide permiso nativo (Permitir / No permitir) antes de abrir cámara o galería.
///
/// En iOS la galería usa PHPicker y no requiere permiso de fotos de antemano.
Future<MediaPermissionStatus> requestMediaPermission(
  ImageSource source,
) async {
  if (kIsWeb) return MediaPermissionStatus.granted;

  // PHPicker (image_picker en iOS 14+) no necesita NSPhotoLibraryUsageDescription activo.
  if (source == ImageSource.gallery && Platform.isIOS) {
    return MediaPermissionStatus.granted;
  }

  if (source == ImageSource.camera) {
    return _request(Permission.camera);
  }

  if (Platform.isIOS) {
    return _request(Permission.photos);
  }

  if (Platform.isAndroid) {
    final photos = await _request(Permission.photos);
    if (photos == MediaPermissionStatus.granted) {
      return MediaPermissionStatus.granted;
    }
    return _request(Permission.storage);
  }

  return MediaPermissionStatus.granted;
}

/// Compatibilidad con llamadas existentes que esperan un [bool].
Future<bool> ensureMediaPermissionForImageSource(ImageSource source) async {
  final status = await requestMediaPermission(source);
  return status == MediaPermissionStatus.granted;
}

Future<MediaPermissionStatus> _request(Permission permission) async {
  var status = await permission.status;
  if (status.isGranted || status.isLimited) {
    return MediaPermissionStatus.granted;
  }
  if (status.isPermanentlyDenied) {
    return MediaPermissionStatus.permanentlyDenied;
  }

  status = await permission.request();
  if (status.isGranted || status.isLimited) {
    return MediaPermissionStatus.granted;
  }
  if (status.isPermanentlyDenied) {
    return MediaPermissionStatus.permanentlyDenied;
  }
  return MediaPermissionStatus.denied;
}

String mediaPermissionMessage(
    ImageSource source, MediaPermissionStatus status) {
  final isCamera = source == ImageSource.camera;
  switch (status) {
    case MediaPermissionStatus.granted:
      return '';
    case MediaPermissionStatus.denied:
      return isCamera
          ? 'FitConnect necesita acceso a la cámara para tomar fotos.'
          : 'FitConnect necesita acceso a tus fotos para elegir una imagen.';
    case MediaPermissionStatus.permanentlyDenied:
      return isCamera
          ? 'El permiso de cámara está desactivado. Ábrelo en Ajustes del dispositivo.'
          : 'El permiso de fotos está desactivado. Ábrelo en Ajustes del dispositivo.';
  }
}

/// Muestra un aviso contextual y ofrece abrir Ajustes si el permiso fue bloqueado.
void showMediaPermissionSnackBar(
  BuildContext context,
  ImageSource source,
  MediaPermissionStatus status,
) {
  final message = mediaPermissionMessage(source, status);
  if (message.isEmpty) return;

  final openSettings = status == MediaPermissionStatus.permanentlyDenied;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      action: openSettings
          ? SnackBarAction(
              label: 'Ajustes',
              onPressed: openAppSettings,
            )
          : null,
    ),
  );
}
