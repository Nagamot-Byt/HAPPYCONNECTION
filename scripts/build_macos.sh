#!/bin/bash

echo ""
echo "🏥 HAPPYCONNECTION v2.0 - Compilador macOS"
echo "============================================"
echo ""

echo "Compilando backend Go..."
cd backend
go build -o ../dist/happyconnection-backend
cd ..

echo ""
echo "Compilando app Flutter..."
cd flutter
flutter pub get
flutter build macos --release
cd ..

echo ""
echo "Empaquetando .app..."
mkdir -p dist/HAPPYCONNECTION
cp -r flutter/build/macos/Build/Products/Release/happyconnection.app dist/HAPPYCONNECTION/
cp config/hospital_config.json dist/HAPPYCONNECTION/

echo ""
echo "✅ Compilación completada"
echo "📁 App en: dist/HAPPYCONNECTION/happyconnection.app"
echo ""
