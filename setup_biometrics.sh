#!/bin/bash
# =============================================================================
# setup_biometrics.sh
# Configura Face ID (iOS) y Huella/BiometricAuth (Android) automáticamente.
#
# INSTRUCCIONES (ejecutar en Mac desde la carpeta raíz del proyecto):
#   chmod +x setup_biometrics.sh
#   ./setup_biometrics.sh
# =============================================================================

echo "======================================"
echo " Configuración de Biometría (FitConnect)"
echo "======================================"
echo ""

PLIST="ios/Runner/Info.plist"

if [ ! -f "$PLIST" ]; then
  echo "⚠️  iOS: No se encontró $PLIST (omitiendo configuración iOS)"
else
  if grep -q "NSFaceIDUsageDescription" "$PLIST"; then
    echo "✅ iOS: NSFaceIDUsageDescription ya está configurado."
  else
    /usr/libexec/PlistBuddy -c "Add :NSFaceIDUsageDescription string 'FitConnect usa Face ID para iniciar sesión de forma segura.'" "$PLIST" 2>/dev/null
    if grep -q "NSFaceIDUsageDescription" "$PLIST"; then
      echo "✅ iOS: Permiso Face ID añadido correctamente."
    else
      sed -i '' 's|</dict>|\t<key>NSFaceIDUsageDescription</key>\n\t<string>FitConnect usa Face ID para iniciar sesión de forma segura.</string>\n</dict>|' "$PLIST"
      echo "✅ iOS: Permiso Face ID añadido (método alternativo)."
    fi
  fi
fi

echo ""

MANIFEST="android/app/src/main/AndroidManifest.xml"

if [ ! -f "$MANIFEST" ]; then
  echo "⚠️  Android: No se encontró $MANIFEST (omitiendo configuración Android)"
else
  if grep -q "USE_BIOMETRIC" "$MANIFEST"; then
    echo "✅ Android: Permiso USE_BIOMETRIC ya configurado."
  else
    sed -i '' 's|<application|<uses-permission android:name="android.permission.USE_BIOMETRIC"/>\n    <uses-permission android:name="android.permission.USE_FINGERPRINT"/>\n    <application|' "$MANIFEST"
    echo "✅ Android: Permisos USE_BIOMETRIC y USE_FINGERPRINT añadidos."
  fi
fi

MAIN_ACTIVITY=$(find android/app/src/main -name "MainActivity.kt" 2>/dev/null | head -n 1)

if [ -z "$MAIN_ACTIVITY" ]; then
  MAIN_ACTIVITY=$(find android/app/src/main -name "MainActivity.java" 2>/dev/null | head -n 1)
fi

if [ -z "$MAIN_ACTIVITY" ]; then
  echo "⚠️  Android: No se encontró MainActivity.kt/java"
else
  if grep -q "FlutterFragmentActivity" "$MAIN_ACTIVITY"; then
    echo "✅ Android: MainActivity ya usa FlutterFragmentActivity."
  else
    sed -i '' 's|io.flutter.embedding.android.FlutterActivity|io.flutter.embedding.android.FlutterFragmentActivity|g' "$MAIN_ACTIVITY"
    sed -i '' 's|FlutterActivity()|FlutterFragmentActivity()|g' "$MAIN_ACTIVITY"
    sed -i '' 's|extends FlutterActivity|extends FlutterFragmentActivity|g' "$MAIN_ACTIVITY"
    echo "✅ Android: MainActivity actualizada a FlutterFragmentActivity."
  fi
fi

echo ""
echo "======================================"
echo " ¡Configuración completada!"
echo " Ejecuta 'flutter run' para compilar."
echo "======================================"
