#!/bin/bash

echo ""
echo "📦 HAPPYCONNECTION v2.0 - Instalador Universal de Un Clic"
echo "========================================================="
echo ""

set -e

# Detectar SO
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
else
    OS="windows"
fi

echo "🔍 Sistema detectado: $OS"
echo ""

# Función de instalación
install_happyconnection() {
    echo "📥 Descargando HAPPYCONNECTION..."
    
    if [ "$OS" = "linux" ]; then
        INSTALL_DIR="$HOME/.local/opt/happyconnection"
        mkdir -p "$INSTALL_DIR"
        
        echo "📋 Compilando aplicación para Linux..."
        cd flutter
        flutter pub get
        flutter build linux --release
        cp -r build/linux/x64/release/bundle/* "$INSTALL_DIR/"
        cd ..
        
        # Crear acceso directo
        mkdir -p "$HOME/.local/share/applications"
        cat > "$HOME/.local/share/applications/happyconnection.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=HAPPYCONNECTION
Comment=Conexión RDP Segura al Hospital
Exec=$INSTALL_DIR/happyconnection
Icon=hospital
Categories=Office;Network;
EOF
        
        echo "✅ Instalado en: $INSTALL_DIR"
        
    elif [ "$OS" = "macos" ]; then
        INSTALL_DIR="/Applications/HAPPYCONNECTION.app"
        
        echo "📋 Compilando aplicación para macOS..."
        cd flutter
        flutter pub get
        flutter build macos --release
        cp -r build/macos/Build/Products/Release/happyconnection.app /Applications/
        cd ..
        
        echo "✅ Instalado en: $INSTALL_DIR"
        
    fi
    
    echo ""
    echo "✅ HAPPYCONNECTION instalado exitosamente"
    echo ""
    echo "📍 Ubicación: $INSTALL_DIR"
    echo "🚀 Para ejecutar:"
    if [ "$OS" = "linux" ]; then
        echo "   happyconnection"
    elif [ "$OS" = "macos" ]; then
        echo "   open /Applications/HAPPYCONNECTION.app"
    fi
    echo ""
    echo "🏢 Hospital configurado:"
    echo "   • Nombre: Hospital Universitario del Valle (HUV)"
    echo "   • Servidores: 5 disponibles"
    echo "   • Ubicación: Cali, Colombia"
    echo ""
}

install_happyconnection
