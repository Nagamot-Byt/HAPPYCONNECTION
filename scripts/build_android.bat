@echo off
setlocal EnableExtensions
title MedLink Connect - Build Android (1 clic)
pushd "%~dp0.." >nul
set "ROOT=%CD%"

echo ========================================================
echo        MedLink Connect - Compilacion Android
echo ========================================================
echo.

call :find_flutter
if errorlevel 1 goto :fail

set "VERSION="
for /f "tokens=2 delims=:+" %%V in ('findstr /b "version:" pubspec.yaml') do set "VERSION=%%V"
if defined VERSION set "VERSION=%VERSION: =%"
if not defined VERSION set "VERSION=0.1.0"

echo [1/4] Verificando Flutter...
call flutter --version
if errorlevel 1 goto :fail

echo.
echo [2/4] Descargando dependencias...
call flutter pub get
if errorlevel 1 goto :fail

echo.
echo [3/4] Compilando APK release...
call flutter build apk --release
if errorlevel 1 goto :fail

set "DIST=%ROOT%\dist\Android"
if not exist "%DIST%" mkdir "%DIST%"
set "APK=%ROOT%\build\app\outputs\flutter-apk\app-release.apk"
if not exist "%APK%" (
  echo ERROR: No se genero el APK en %APK%
  goto :fail
)
copy /Y "%APK%" "%DIST%\MedLinkConnect_%VERSION%.apk" >nul

echo.
echo [4/4] Compilando App Bundle (AAB)...
call flutter build appbundle --release
if errorlevel 1 (
  echo ADVERTENCIA: No se pudo generar el AAB; el APK si esta disponible.
) else (
  if exist "%ROOT%\build\app\outputs\bundle\release\app-release.aab" (
    copy /Y "%ROOT%\build\app\outputs\bundle\release\app-release.aab" "%DIST%\MedLinkConnect_%VERSION%.aab" >nul
  )
)

echo.
echo ========================================================
echo   Compilacion completada. Artefactos en dist\Android:
echo   - MedLinkConnect_%VERSION%.apk
echo   - MedLinkConnect_%VERSION%.aab
echo ========================================================
echo.
echo Nota: release usa la clave de debug. Configura un keystore
echo en android\key.properties para distribucion real.
echo.
popd >nul
pause
exit /b 0

:find_flutter
where flutter >nul 2>nul
if not errorlevel 1 exit /b 0
for %%D in (
  "%LOCALAPPDATA%\flutter\bin"
  "%USERPROFILE%\flutter\bin"
  "C:\flutter\bin"
  "D:\flutter\bin"
) do (
  if exist "%%~D\flutter.bat" (
    set "PATH=%%~D;%PATH%"
    exit /b 0
  )
)
echo ERROR: Flutter no esta en PATH.
exit /b 1

:fail
echo.
echo ========================================================
echo   La compilacion Android fallo.
echo   Verifica Android SDK, Java y las licencias de Gradle.
echo ========================================================
popd >nul
pause
exit /b 1
