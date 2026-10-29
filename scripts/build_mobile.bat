@echo off
setlocal EnableExtensions
title MedLink Connect - Build Mobile (1 clic)
echo ========================================================
echo        MedLink Connect - Compilacion movil
echo ========================================================
echo.
echo [Android]
call "%~dp0build_android.bat"
if errorlevel 1 exit /b 1

echo.
echo ========================================================
echo   iOS no se puede compilar desde Windows.
echo   Ejecuta scripts/build_ios.sh en macOS con Xcode.
echo ========================================================
echo.
exit /b 0
