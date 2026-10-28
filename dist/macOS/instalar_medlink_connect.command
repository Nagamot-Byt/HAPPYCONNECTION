#!/usr/bin/env bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

echo "========================================================"
echo "          Instalador 1-Click - MedLink Connect (macOS)"
echo "========================================================"
echo ""

APP_NAME="MedLink Connect.app"
DEST_DIR="/Applications"

if [ -d "$APP_NAME" ]; then
    echo "[1/2] Copiando $APP_NAME a $DEST_DIR..."
    cp -R "$APP_NAME" "$DEST_DIR/"
    echo "[2/2] Configurando permisos de seguridad..."
    xattr -cr "$DEST_DIR/$APP_NAME" 2>/dev/null || true
    echo ""
    echo "========================================================"
    echo "  ¡Instalación completada exitosamente!"
    echo "  Ya puedes abrir MedLink Connect desde tu carpeta de"
    echo "  Aplicaciones o desde Launchpad."
    echo "========================================================"
else
    echo "ERROR: Coloque el archivo '$APP_NAME' en esta misma carpeta"
    echo "antes de ejecutar este instalador."
fi
echo ""
read -p "Presiona Enter para cerrar esta ventana..."
