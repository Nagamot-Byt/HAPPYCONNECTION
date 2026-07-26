#!/bin/bash

echo ""
echo "🏥 HAPPYCONNECTION v2.0 - Compilador Linux"
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
flutter build linux --release
cd ..

echo ""
echo "Empaquetando binario..."
mkdir -p dist/HAPPYCONNECTION
cp flutter/build/linux/x64/release/bundle/happyconnection dist/HAPPYCONNECTION/
cp config/hospital_config.json dist/HAPPYCONNECTION/
chmod +x dist/HAPPYCONNECTION/happyconnection

echo ""
echo "✅ Compilación completada"
echo "📁 Binario en: dist/HAPPYCONNECTION/happyconnection"
echo ""
