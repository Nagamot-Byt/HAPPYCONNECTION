@echo off
REM HAPPYCONNECTION v2.0 - Instalador de Un Clic (Windows)
REM Este script instala HAPPYCONNECTION con un solo clic

setlocal enabledelayedexpansion

echo.
echo 📦 HAPPYCONNECTION v2.0 - Instalador Universal de Un Clic
echo =========================================================
echo.

REM Detectar arquitectura
if "%PROCESSOR_ARCHITECTURE%"=="AMD64" (
    set ARCH=x64
) else (
    set ARCH=x86
)

echo 🔍 Sistema: Windows (%ARCH%)
echo.

set INSTALL_DIR=%ProgramFiles%\HAPPYCONNECTION

echo 📥 Preparando instalación...
echo    • Ubicación: %INSTALL_DIR%
echo.

REM Crear directorio de instalación
if not exist "%INSTALL_DIR%" (
    mkdir "%INSTALL_DIR%"
    echo ✅ Directorio creado
) else (
    echo ⚠️ Directorio ya existe, actualizando...
)

echo.
echo 📋 Compilando aplicación Flutter...
cd flutter
call flutter pub get > nul 2>&1
if errorlevel 1 (
    echo ❌ Error descargando dependencias Flutter
    exit /b 1
)

call flutter build windows --release > nul 2>&1
if errorlevel 1 (
    echo ❌ Error compilando Flutter
    exit /b 1
)
echo ✅ Flutter compilado

echo.
echo 📦 Copiando archivos...
xcopy /S /I /Y "build\windows\%ARCH%\runner\Release\*" "%INSTALL_DIR%" > nul
if errorlevel 1 (
    echo ❌ Error copiando archivos
    exit /b 1
)
echo ✅ Archivos copiados

cd ..

echo.
echo 🔧 Compilando backend...
cd backend
go build -o "..\%INSTALL_DIR%\happyconnection-backend.exe" main.go
if errorlevel 1 (
    echo ❌ Error compilando backend
    exit /b 1
)
echo ✅ Backend compilado
cd ..

echo.
echo 📋 Copiando configuración...
xcopy /S /I /Y config\* "%INSTALL_DIR%\config\" > nul
echo ✅ Configuración copiada

echo.
echo 🔗 Creando accesos directos...

REM Crear acceso directo en escritorio
powershell -Command "$TargetPath = '%INSTALL_DIR%\happyconnection.exe'; $DesktopPath = [Environment]::GetFolderPath('Desktop'); $ShortcutPath = Join-Path -Path $DesktopPath -ChildPath 'HAPPYCONNECTION.lnk'; $WshShell = New-Object -ComObject WScript.Shell; $Shortcut = $WshShell.CreateShortcut($ShortcutPath); $Shortcut.TargetPath = $TargetPath; $Shortcut.Save()"

echo ✅ Acceso directo en escritorio

echo.
echo ================================================
echo ✅ INSTALACIÓN COMPLETADA
echo ================================================
echo.
echo 📍 Ubicación: %INSTALL_DIR%
echo 🚀 Para ejecutar: Buscar 'HAPPYCONNECTION' en el menú Inicio
echo.
echo 🏢 Hospital configurado:
echo    • Nombre: Hospital Universitario del Valle (HUV)
echo    • Servidores: 5 disponibles
echo    • Ubicación: Cali, Colombia
echo.
echo 📋 Servidores disponibles:
echo    1. Servidor Pediátrico (👶)
echo    2. Servidor Ginecológico (👩‍⚕️)
echo    3. Servidor Móviles (📱)
echo    4. Servidor Urgencias (🚑 - PRIORITARIO)
echo    5. Servidor Consulta Externa (🏥)
echo.
echo 💡 Próximos pasos:
echo    1. Ejecutar HAPPYCONNECTION desde el escritorio
echo    2. Seleccionar servidor a conectarse
echo    3. Ingresar credenciales del hospital
echo    4. ¡Listo para usar!
echo.
pause
