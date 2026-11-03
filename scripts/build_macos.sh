#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

BIN_NAME="medlink_connect"
APP_NAME="MedLink Connect"
DIST_DIR="$ROOT_DIR/dist/macOS"
STAGE_DIR="$ROOT_DIR/build/packaging/macos"
APP_BUILD="$ROOT_DIR/build/macos/Build/Products/Release/${BIN_NAME}.app"
DMG_FILE="$DIST_DIR/MedLinkConnect_macOS.dmg"

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
fail() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "Este empaquetado debe ejecutarse en macOS."
command -v flutter >/dev/null 2>&1 || fail "Flutter no está instalado o no está en PATH."
command -v hdiutil >/dev/null 2>&1 || fail "hdiutil no está disponible."
command -v ditto >/dev/null 2>&1 || fail "ditto no está disponible."

log "Verificando Flutter"
flutter --version | sed -n '1p'

log "Habilitando macOS desktop"
flutter config --enable-macos-desktop >/dev/null

log "Descargando dependencias"
flutter pub get

log "Instalando pods de macOS"
(cd macos && pod install)

log "Compilando macOS release"
flutter build macos --release

[ -d "$APP_BUILD" ] || fail "No se generó la aplicación esperada en $APP_BUILD"

log "Preparando DMG"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR" "$DIST_DIR"
ditto "$APP_BUILD" "$STAGE_DIR/$APP_NAME.app"
ln -s /Applications "$STAGE_DIR/Applications"
cp "$ROOT_DIR/dist/macOS/README_MACOS.txt" "$STAGE_DIR/README_MACOS.txt"
rm -f "$DMG_FILE"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE_DIR" \
  -ov -format UDZO \
  "$DMG_FILE"
hdiutil verify "$DMG_FILE"

log "Generando checksum"
(cd "$DIST_DIR" && shasum -a 256 "$(basename "$DMG_FILE")" > SHA256SUMS-macOS.txt)

log "Artefacto generado en dist/macOS"
ls -lh "$DIST_DIR"
printf '\nListo. Abre MedLinkConnect_macOS.dmg y arrastra MedLink Connect.app a Applications.\n'
