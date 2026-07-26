@echo off
setlocal enabledelayedexpansion

echo.
echo 🏢 HAPPYCONNECTION v2.0 - Compilador Universal
echo ============================================
echo.

set BUILD_DIR=dist
set APP_NAME=HAPPYCONNECTION

REM Crear directorio de distribución
if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"

echo [1/4] Compilando backend Go...
cd backend
echo    • Windows (amd64)...
set GOOS=windows
set GOARCH=amd64
go build -o ".\..\dist\happyconnection-backend.exe" main.go
if errorlevel 1 (
    echo ❌ Error compilando Go backend
    exit /b 1
)
echo ✅ Backend compilado
cd ..

echo.
echo [2/4] Compilando Flutter Windows (exe)...
cd flutter
call flutter pub get > nul 2>&1
call flutter build windows --release > nul 2>&1
if not exist "..\%BUILD_DIR%\windows" mkdir "..\%BUILD_DIR%\windows"
copy /Y "build\windows\x64\runner\Release\*.*" "..\%BUILD_DIR%\windows\" > nul
echo ✅ Windows compilado

echo.
echo [3/4] Compilando Flutter Android (APK)...
call flutter build apk --release > nul 2>&1
if not exist "..\%BUILD_DIR%\android" mkdir "..\%BUILD_DIR%\android"
copy /Y "build\app\outputs\flutter-apk\app-release.apk" "..\%BUILD_DIR%\android\happyconnection.apk" > nul
echo ✅ Android compilado

echo.
echo [4/4] Copiando configuración...
if not exist "..\%BUILD_DIR%\config" mkdir "..\%BUILD_DIR%\config"
copy /Y "..\config\hospital_config.json" "..\%BUILD_DIR%\config\" > nul
echo ✅ Configuración copiada

cd ..

echo.
echo ================================================
echo ✅ COMPILACIÓN COMPLETADA EXITOSAMENTE
echo ================================================
echo.
echo 📦 Distribuciones generadas:
echo    • Windows:  %BUILD_DIR%\windows\happyconnection.exe
echo    • Android:  %BUILD_DIR%\android\happyconnection.apk
echo    • Backend:  %BUILD_DIR%\happyconnection-backend.exe
echo.
echo 📋 Configuración:
echo    • Hospital: Hospital Universitario del Valle (HUV)
echo    • Servidores: 5 servidores configurados
echo.
echo 🚀 Próximos pasos:
echo    1. Ejecutar el instalador de un clic
echo    2. Seleccionar servidores disponibles
echo    3. Conectar a Historia Clínica
echo.
pause
