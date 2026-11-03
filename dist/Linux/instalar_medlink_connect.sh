#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
cd "$DIR"

echo "========================================================"
echo "          Instalador 1-Click - MedLink Connect (Linux)"
echo "========================================================"
echo ""

if [ ! -x "bundle/medlink_connect" ]; then
    echo "ERROR: Falta bundle/medlink_connect."
    echo "Genera el paquete con scripts/build_linux.sh."
    exit 1
fi

CURRENT_USER="$(id -un)"
TARGET_USER="$CURRENT_USER"
TARGET_HOME="$HOME"

if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
    TARGET_USER="${SUDO_USER}"
    TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
    if [ -z "$TARGET_HOME" ] || [ ! -d "$TARGET_HOME" ]; then
        echo "ERROR: No se pudo determinar el directorio personal de $TARGET_USER."
        exit 1
    fi
fi

if [ "$(id -u)" -eq 0 ] && [ "$TARGET_USER" = "root" ]; then
    echo "ERROR: No ejecutes este instalador como root."
    echo "Haz doble clic en el archivo .run con tu usuario normal, sin sudo."
    exit 1
fi

APP_DIR="$TARGET_HOME/.local/share/medlink_connect"
BIN_DIR="$TARGET_HOME/.local/bin"
DESKTOP_DIR="$TARGET_HOME/.local/share/applications"

echo "[1/3] Instalando archivos en $APP_DIR..."
mkdir -p "$APP_DIR" "$BIN_DIR" "$DESKTOP_DIR"
cp -a bundle/. "$APP_DIR/"
chmod +x "$APP_DIR/medlink_connect"
ln -sfn "$APP_DIR/medlink_connect" "$BIN_DIR/medlink_connect"

if [ ! -x "$APP_DIR/medlink_connect" ]; then
    echo "ERROR: No se pudo instalar el ejecutable en $APP_DIR/medlink_connect."
    exit 1
fi

ICON_PATH="$APP_DIR/medlink_connect.png"
if [ ! -f "$ICON_PATH" ]; then
    ICON_PATH="network-wireless"
fi

echo "[2/3] Registrando aplicación en el menú del sistema (.desktop)..."
cat << EOF > "$DESKTOP_DIR/medlink_connect.desktop"
[Desktop Entry]
Version=1.0
Name=MedLink Connect
Comment=Conexión segura RDP y Wi-Fi para redes hospitalarias
Exec="$APP_DIR/medlink_connect"
Icon=$ICON_PATH
Path=$APP_DIR
Terminal=false
Type=Application
Categories=Network;Utility;
StartupWMClass=medlink_connect
EOF

chmod +x "$DESKTOP_DIR/medlink_connect.desktop"

echo "[3/3] Creando acceso directo en el Escritorio..."
USER_DESKTOP=""
if [ "$TARGET_USER" = "$CURRENT_USER" ] && command -v xdg-user-dir >/dev/null 2>&1; then
    CONFIGURED_DESKTOP="$(xdg-user-dir DESKTOP 2>/dev/null || true)"
    if [ -n "$CONFIGURED_DESKTOP" ] && [ "$CONFIGURED_DESKTOP" != "$TARGET_HOME" ] && [ -d "$CONFIGURED_DESKTOP" ]; then
        USER_DESKTOP="$CONFIGURED_DESKTOP"
    fi
fi
if [ -z "$USER_DESKTOP" ] && [ -d "$TARGET_HOME/Escritorio" ]; then
    USER_DESKTOP="$TARGET_HOME/Escritorio"
fi
if [ -z "$USER_DESKTOP" ] && [ -d "$TARGET_HOME/Desktop" ]; then
    USER_DESKTOP="$TARGET_HOME/Desktop"
fi

if [ -n "$USER_DESKTOP" ]; then
    cp "$DESKTOP_DIR/medlink_connect.desktop" "$USER_DESKTOP/"
    chmod +x "$USER_DESKTOP/medlink_connect.desktop" 2>/dev/null || true
    gio set "$USER_DESKTOP/medlink_connect.desktop" metadata::trusted true 2>/dev/null || true
fi

if [ "$(id -u)" -eq 0 ]; then
    TARGET_GROUP="$(id -gn "$TARGET_USER")"
    chown "$TARGET_USER:$TARGET_GROUP" \
        "$TARGET_HOME/.local" \
        "$TARGET_HOME/.local/share" \
        "$BIN_DIR" \
        "$DESKTOP_DIR" 2>/dev/null || true
    chown -R "$TARGET_USER:$TARGET_GROUP" "$APP_DIR" "$DESKTOP_DIR/medlink_connect.desktop"
    chown -h "$TARGET_USER:$TARGET_GROUP" "$BIN_DIR/medlink_connect" 2>/dev/null || true
    if [ -n "$USER_DESKTOP" ] && [ -f "$USER_DESKTOP/medlink_connect.desktop" ]; then
        chown "$TARGET_USER:$TARGET_GROUP" "$USER_DESKTOP/medlink_connect.desktop"
    fi
fi

echo ""
echo "========================================================"
echo "  ¡Instalación completada exitosamente!"
echo "  Ejecutable: $APP_DIR/medlink_connect"
echo "  Ya puedes abrir MedLink Connect desde tu menú de aplicaciones"
echo "  o desde tu Escritorio."
echo "========================================================"
echo ""
