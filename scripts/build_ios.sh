#!/usr/bin/env bash
# Compilación y empaquetado en un clic para iOS (solo macOS).
#
# Uso:
#   ./scripts/build_ios.sh              # app sin firma para dispositivo
#   ./scripts/build_ios.sh --simulator  # app para el simulador
#   ./scripts/build_ios.sh --ipa        # IPA firmada (requiere equipo/certificados)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

DIST_DIR="$ROOT_DIR/dist/iOS"
VERSION="$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml | cut -d+ -f1)"
VERSION="${VERSION:-0.1.0}"
MODE="${1:-device}"

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
fail() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "La compilación iOS requiere macOS con Xcode."

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
command -v xcodebuild >/dev/null 2>&1 || fail "Xcode no está instalado."

log "Verificando Flutter"
flutter --version | sed -n '1p'

log "Descargando dependencias"
flutter pub get

mkdir -p "$DIST_DIR"

case "$MODE" in
  --simulator|simulator)
    log "Compilando iOS para simulador (debug, sin firma)"
    flutter build ios --simulator --debug --no-codesign
    APP_PATH="$ROOT_DIR/build/ios/iphonesimulator/Runner.app"
    OUT="$DIST_DIR/MedLinkConnect_${VERSION}_simulator.app.zip"
    ;;
  --ipa|ipa)
    log "Compilando IPA firmada"
    flutter build ipa --release
    IPA_PATH="$(find "$ROOT_DIR/build/ios/ipa" -maxdepth 1 -name '*.ipa' | head -1 || true)"
    [ -n "$IPA_PATH" ] || fail "No se generó ningún .ipa. Revisa la firma en Xcode."
    cp "$IPA_PATH" "$DIST_DIR/MedLinkConnect_${VERSION}.ipa"
    log "Artefacto generado en dist/iOS"
    ls -lh "$DIST_DIR"
    exit 0
    ;;
  *)
    log "Compilando iOS para dispositivo (release, sin firma)"
    flutter build ios --release --no-codesign
    APP_PATH="$ROOT_DIR/build/ios/iphoneos/Runner.app"
    OUT="$DIST_DIR/MedLinkConnect_${VERSION}_unsigned.app.zip"
    ;;
esac

[ -d "$APP_PATH" ] || fail "No se encontró la app compilada en $APP_PATH"

log "Empaquetando $APP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$OUT"

log "Artefacto generado en dist/iOS"
ls -lh "$DIST_DIR"
printf '\nNota: para instalar en un dispositivo real necesitas firma de Apple.\n'
printf 'Usa ./scripts/build_ios.sh --ipa con un equipo y certificados configurados.\n'
