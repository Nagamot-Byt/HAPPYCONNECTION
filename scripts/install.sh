#!/bin/bash

echo "🏥 HAPPYCONNECTION v2.0 - Instalador"
echo "===================================="

OS=$(uname -s)
echo "Sistema operativo detectado: $OS"

if [[ $OS == "Darwin" ]]; then
    echo "📱 Detectado: macOS"
    echo "Instalando dependencias con Homebrew..."
    brew install go flutter
    
elif [[ $OS == "Linux" ]]; then
    echo "🐧 Detectado: Linux"
    echo "Instalando dependencias..."
    sudo apt-get update
    sudo apt-get install -y golang flutter
    
fi

echo "\n✅ Instalación completada"
echo "\nPróximos pasos:"
echo "1. cd flutter && flutter pub get"
echo "2. flutter run"
