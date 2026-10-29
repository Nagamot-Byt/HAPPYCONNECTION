#!/usr/bin/env bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

echo "========================================================"
echo "          Instalador 1-Click - MedLink Connect (Linux)"
echo "========================================================"
echo ""

APP_DIR="$HOME/.local/share/medlink_connect"
BIN_DIR="$HOME/.local/bin"
DESKTOP_DIR="$HOME/.local/share/applications"

if [ ! -x "bundle/medlink_connect" ]; then
    echo "ERROR: Falta bundle/medlink_connect."
    echo "Genera el paquete con scripts/build_linux.sh."
    exit 1
fi

echo "[1/3] Instalando archivos en $APP_DIR..."
mkdir -p "$APP_DIR" "$BIN_DIR" "$DESKTOP_DIR"
cp -a bundle/. "$APP_DIR/"
chmod +x "$APP_DIR/medlink_connect"
ln -sf "$APP_DIR/medlink_connect" "$BIN_DIR/medlink_connect"

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
Exec=$APP_DIR/medlink_connect
TryExec=$APP_DIR/medlink_connect
Icon=$ICON_PATH
Terminal=false
Type=Application
Categories=Network;Utility;
StartupWMClass=medlink_connect
EOF

chmod +x "$DESKTOP_DIR/medlink_connect.desktop"

echo "[3/3] Creando acceso directo en el Escritorio..."
if [ -d "$HOME/Escritorio" ]; then
    cp "$DESKTOP_DIR/medlink_connect.desktop" "$HOME/Escritorio/"
    chmod +x "$HOME/Escritorio/medlink_connect.desktop" 2>/dev/null || true
    gio set "$HOME/Escritorio/medlink_connect.desktop" metadata::trusted true 2>/dev/null || true
elif [ -d "$HOME/Desktop" ]; then
    cp "$DESKTOP_DIR/medlink_connect.desktop" "$HOME/Desktop/"
    chmod +x "$HOME/Desktop/medlink_connect.desktop" 2>/dev/null || true
    gio set "$HOME/Desktop/medlink_connect.desktop" metadata::trusted true 2>/dev/null || true
fi

echo ""
echo "========================================================"
echo "  ¡Instalación completada exitosamente!"
echo "  Ya puedes abrir MedLink Connect desde tu menú de aplicaciones"
echo "  o desde tu Escritorio."
echo "========================================================"
echo ""
