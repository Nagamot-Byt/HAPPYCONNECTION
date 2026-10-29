#!/usr/bin/env bash
# Compilación y empaquetado en un clic para Linux.
# Genera un .run autoejecutable, un .tar.gz portable y, si es posible, un .deb.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

BIN_NAME="medlink_connect"
DIST_DIR="$ROOT_DIR/dist/Linux"
STAGE_DIR="$ROOT_DIR/build/packaging/linux"
ICON_SRC="$ROOT_DIR/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png"
VERSION="$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml | cut -d+ -f1)"
VERSION="${VERSION:-0.1.0}"

case "$(uname -m)" in
  x86_64)  FLUTTER_ARCH="x64";   DEB_ARCH="amd64" ;;
  aarch64|arm64) FLUTTER_ARCH="arm64"; DEB_ARCH="arm64" ;;
  *)       FLUTTER_ARCH="$(uname -m)"; DEB_ARCH="$(uname -m)" ;;
esac

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
fail() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

find_flutter() {
  command -v flutter >/dev/null 2>&1 && return 0
  local candidate
  for candidate in \
    "$HOME/flutter/bin" \
    "$HOME/development/flutter/bin" \
    "/opt/flutter/bin" \
    "/usr/local/flutter/bin" \
    "/snap/bin"; do
    if [ -x "$candidate/flutter" ]; then
      export PATH="$candidate:$PATH"
      return 0
    fi
  done
  return 1
}

find_flutter || fail "Flutter no está instalado o no está en PATH."

log "Verificando Flutter"
flutter --version | sed -n '1p'

log "Descargando dependencias"
flutter pub get

log "Compilando Linux release"
flutter build linux --release

BUNDLE_SRC="$ROOT_DIR/build/linux/$FLUTTER_ARCH/release/bundle"
[ -x "$BUNDLE_SRC/$BIN_NAME" ] || fail "No se generó el bundle esperado en $BUNDLE_SRC"

log "Preparando paquete portable"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR/bundle" "$DIST_DIR"
cp -a "$BUNDLE_SRC/." "$STAGE_DIR/bundle/"
cp "$ROOT_DIR/dist/Linux/instalar_medlink_connect.sh" "$STAGE_DIR/"
cp "$ROOT_DIR/dist/Linux/README_LINUX.txt" "$STAGE_DIR/"
if [ -f "$ICON_SRC" ]; then
  cp "$ICON_SRC" "$STAGE_DIR/bundle/medlink_connect.png"
fi
chmod +x "$STAGE_DIR/instalar_medlink_connect.sh" "$STAGE_DIR/bundle/$BIN_NAME"

TARBALL="$DIST_DIR/MedLinkConnect_Linux_${FLUTTER_ARCH}.tar.gz"
tar -C "$STAGE_DIR" -czf "$TARBALL" \
  bundle instalar_medlink_connect.sh README_LINUX.txt

log "Creando instalador autoejecutable (.run)"
PAYLOAD="$ROOT_DIR/build/packaging/linux-payload.tar.gz"
RUN_FILE="$DIST_DIR/MedLinkConnect_Linux_${FLUTTER_ARCH}.run"
tar -C "$STAGE_DIR" -czf "$PAYLOAD" \
  bundle instalar_medlink_connect.sh README_LINUX.txt
{
  cat <<'HEADER'
#!/bin/sh
# Instalador autoejecutable de MedLink Connect para Linux.
set -eu
SELF="$0"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT INT TERM
LINE="$(awk '/^__MEDLINK_PAYLOAD__$/ {print NR + 1; exit}' "$SELF")"
if [ -z "${LINE:-}" ]; then
  echo "Paquete corrupto: no se encontró el payload." >&2
  exit 1
fi
tail -n +"$LINE" "$SELF" | tar -xz -C "$TMPDIR"
chmod +x "$TMPDIR/instalar_medlink_connect.sh"
"$TMPDIR/instalar_medlink_connect.sh"
exit 0
HEADER
  printf '__MEDLINK_PAYLOAD__\n'
  cat "$PAYLOAD"
} > "$RUN_FILE"
chmod +x "$RUN_FILE"
rm -f "$PAYLOAD"

if command -v dpkg-deb >/dev/null 2>&1; then
  log "Generando paquete .deb"
  DEB_ROOT="$ROOT_DIR/build/packaging/deb"
  rm -rf "$DEB_ROOT"
  mkdir -p \
    "$DEB_ROOT/DEBIAN" \
    "$DEB_ROOT/usr/bin" \
    "$DEB_ROOT/usr/lib/medlink-connect" \
    "$DEB_ROOT/usr/share/applications" \
    "$DEB_ROOT/usr/share/icons/hicolor/256x256/apps"
  cp -a "$STAGE_DIR/bundle/." "$DEB_ROOT/usr/lib/medlink-connect/"
  if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$DEB_ROOT/usr/share/icons/hicolor/256x256/apps/medlink-connect.png"
  fi
  cat > "$DEB_ROOT/usr/bin/medlink-connect" <<'EOF'
#!/bin/sh
exec /usr/lib/medlink-connect/medlink_connect "$@"
EOF
  chmod +x "$DEB_ROOT/usr/bin/medlink-connect"
  cat > "$DEB_ROOT/usr/share/applications/medlink-connect.desktop" <<'EOF'
[Desktop Entry]
Version=1.0
Name=MedLink Connect
Comment=Conexión RDP y Wi-Fi para redes hospitalarias
Exec=medlink-connect
Icon=medlink-connect
Terminal=false
Type=Application
Categories=Network;Utility;
EOF
  cat > "$DEB_ROOT/DEBIAN/control" <<EOF
Package: medlink-connect
Version: $VERSION
Section: net
Priority: optional
Architecture: $DEB_ARCH
Maintainer: MedLink Health Technology <soporte@medlink.local>
Depends: libgtk-3-0, libsecret-1-0
Description: Acceso guiado a escritorios remotos hospitalarios.
 Facilita la conexión Wi-Fi, el túnel dividido por rutas y el
 lanzamiento del cliente RDP.
EOF
  dpkg-deb --build --root-owner-group "$DEB_ROOT" \
    "$DIST_DIR/medlink-connect_${VERSION}_${DEB_ARCH}.deb" >/dev/null
fi

log "Artefactos generados en dist/Linux"
ls -lh "$DIST_DIR"
printf '\nListo. Para instalar sin terminal: doble clic en MedLinkConnect_Linux_%s.run\n' "$FLUTTER_ARCH"
