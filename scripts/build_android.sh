#!/usr/bin/env bash
# Compilación y empaquetado en un clic para Android (APK + AAB).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

DIST_DIR="$ROOT_DIR/dist/Android"
VERSION="$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml | cut -d+ -f1)"
VERSION="${VERSION:-0.1.0}"

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
fail() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

find_flutter() {
  command -v flutter >/dev/null 2>&1 && return 0
  local candidate
  for candidate in \
    "$HOME/flutter/bin" \
    "$HOME/development/flutter/bin" \
    "/opt/flutter/bin" \
    "/usr/local/flutter/bin"; do
    if [ -x "$candidate/flutter" ]; then
      export PATH="$candidate:$PATH"
      return 0
    fi
  done
  return 1
}

find_flutter || fail "Flutter no está instalado o no está en PATH."
if ! command -v java >/dev/null 2>&1; then
  printf '\nADVERTENCIA: Java no está en PATH. Flutter usará el JDK de Android Studio si está configurado.\n'
fi

log "Verificando Flutter"
flutter --version | sed -n '1p'

ANDROID_LINE="$(flutter doctor 2>/dev/null | grep "Android toolchain" || true)"
case "$ANDROID_LINE" in
  *"✗"*|"")
    printf '\nADVERTENCIA: Flutter no detecta un Android SDK completo.\n'
    printf 'Instala Android Studio o define ANDROID_HOME/ANDROID_SDK_ROOT.\n'
    printf 'Se intentará compilar de todos modos...\n'
    ;;
esac

log "Descargando dependencias"
flutter pub get

log "Compilando APK release"
flutter build apk --release

APK_SRC="$ROOT_DIR/build/app/outputs/flutter-apk/app-release.apk"
[ -f "$APK_SRC" ] || fail "No se generó el APK esperado en $APK_SRC"
mkdir -p "$DIST_DIR"
cp "$APK_SRC" "$DIST_DIR/MedLinkConnect_${VERSION}.apk"

log "Compilando App Bundle (AAB) para Play Store"
if flutter build appbundle --release; then
  AAB_SRC="$ROOT_DIR/build/app/outputs/bundle/release/app-release.aab"
  if [ -f "$AAB_SRC" ]; then
    cp "$AAB_SRC" "$DIST_DIR/MedLinkConnect_${VERSION}.aab"
  fi
else
  printf 'ADVERTENCIA: no se pudo generar el AAB; el APK sí está disponible.\n'
fi

log "Artefactos generados en dist/Android"
ls -lh "$DIST_DIR"
printf '\nInstala el APK en el telefono copiandolo y abriendolo, o con:\n'
printf '  adb install -r dist/Android/MedLinkConnect_%s.apk\n' "$VERSION"
printf '\nNota: la configuración actual firma release con la clave de debug.\n'
printf 'Para distribución real configura un keystore en android/key.properties.\n'
