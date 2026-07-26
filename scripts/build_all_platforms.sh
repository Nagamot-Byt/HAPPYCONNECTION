#!/bin/bash

set -e

echo ""
echo "🏢 HAPPYCONNECTION v2.0 - Compilador Universal"
echo "=========================================="
echo ""

BUILD_DIR="dist"
APP_NAME="HAPPYCONNECTION"

# Crear directorio de distribución
mkdir -p "$BUILD_DIR"

echo "[1/6] Compilando backend Go..."
cd backend
echo "   • Windows (amd64)..."
GOOS=windows GOARCH=amd64 go build -o "../dist/happyconnection-backend-windows.exe" main.go
echo "   • macOS (amd64)..."
GOOS=darwin GOARCH=amd64 go build -o "../dist/happyconnection-backend-macos-intel" main.go
echo "   • macOS (arm64)..."
GOOS=darwin GOARCH=arm64 go build -o "../dist/happyconnection-backend-macos-arm" main.go
echo "   • Linux (amd64)..."
GOOS=linux GOARCH=amd64 go build -o "../dist/happyconnection-backend-linux" main.go
echo "✅ Backend compilado para todas las plataformas"
cd ..

echo ""
echo "[2/6] Compilando Flutter Windows (exe)..."
cd flutter
flutter pub get > /dev/null 2>&1
flutter build windows --release > /dev/null 2>&1
mkdir -p "../dist/windows"
cp -r build/windows/x64/runner/Release/* ../dist/windows/
echo "✅ Windows .exe compilado"

echo ""
echo "[3/6] Compilando Flutter macOS (app)..."
flutter build macos --release > /dev/null 2>&1
mkdir -p "../dist/macos"
cp -r build/macos/Build/Products/Release/happyconnection.app ../dist/macos/
echo "✅ macOS .app compilado"

echo ""
echo "[4/6] Compilando Flutter Linux (binario)..."
flutter build linux --release > /dev/null 2>&1
mkdir -p "../dist/linux"
cp -r build/linux/x64/release/bundle/* ../dist/linux/
echo "✅ Linux binario compilado"

echo ""
echo "[5/6] Compilando Flutter iOS (ipa)..."
flutter build ios --release > /dev/null 2>&1
mkdir -p "../dist/ios"
echo "✅ iOS preparado (necesita Xcode para .ipa final)"

echo ""
echo "[6/6] Compilando Flutter Android (apk)..."
flutter build apk --release > /dev/null 2>&1
mkdir -p "../dist/android"
cp build/app/outputs/flutter-apk/app-release.apk ../dist/android/happyconnection.apk
echo "✅ Android APK compilado"

cd ..

echo ""
echo "=" * 50
echo "✅ COMPILACIÓN COMPLETADA EXITOSAMENTE"
echo "=" * 50
echo ""
echo "📦 Distribuciones generadas:"
echo "   • Windows:      $BUILD_DIR/windows/happyconnection.exe"
echo "   • macOS (Intel): $BUILD_DIR/macos/happyconnection.app"
echo "   • macOS (ARM):   Autodetectado en app"
echo "   • Linux:        $BUILD_DIR/linux/happyconnection"
echo "   • Android:      $BUILD_DIR/android/happyconnection.apk"
echo "   • iOS:          Usar Xcode desde: flutter/build/ios/"
echo ""
echo "🔧 Backends disponibles:"
echo "   • Windows:      $BUILD_DIR/happyconnection-backend-windows.exe"
echo "   • macOS (Intel): $BUILD_DIR/happyconnection-backend-macos-intel"
echo "   • macOS (ARM):   $BUILD_DIR/happyconnection-backend-macos-arm"
echo "   • Linux:        $BUILD_DIR/happyconnection-backend-linux"
echo ""
echo "📋 Configuración:"
echo "   • Hospital:     config/hospital_config.json"
echo "   • Servidores:   5 servidores HUV configurados"
echo ""
echo "🚀 Próximos pasos:"
echo "   1. Personalizar config/hospital_config.json si es necesario"
echo "   2. Copiar aplicación a las máquinas"
echo "   3. Ejecutar el instalador de un clic"
echo ""
