@echo off
setlocal EnableExtensions
title MedLink Connect - Build Windows (1 clic)
pushd "%~dp0.." >nul
set "ROOT=%CD%"

echo ========================================================
echo        MedLink Connect - Compilacion Windows
echo ========================================================
echo.

call :find_flutter
if errorlevel 1 goto :fail

echo [1/5] Verificando Flutter...
call flutter --version
if errorlevel 1 goto :fail

echo.
echo [2/5] Descargando dependencias...
call flutter pub get
if errorlevel 1 goto :fail

echo.
echo [3/5] Compilando Windows release...
call flutter build windows --release
if errorlevel 1 goto :fail

set "OUT=%ROOT%\build\windows\x64\runner\Release"
if not exist "%OUT%\medlink_connect.exe" (
  echo ERROR: No se genero medlink_connect.exe en %OUT%
  goto :fail
)

echo.
echo [4/5] Preparando paquete portable...
set "DIST=%ROOT%\dist\Windows"
if not exist "%DIST%" mkdir "%DIST%"
if exist "%DIST%\bundle" rmdir /S /Q "%DIST%\bundle"
robocopy "%OUT%" "%DIST%\bundle" /E /NFL /NDL /NJH /NJS /NP >nul
if errorlevel 8 (
  echo ERROR: No se pudo copiar el bundle.
  goto :fail
)
if exist "%DIST%\medlink_connect_admin.bat" (
  copy /Y "%DIST%\medlink_connect_admin.bat" "%DIST%\bundle\" >nul
  copy /Y "%DIST%\medlink_connect_admin.bat" "%OUT%\" >nul
)
if exist "%DIST%\README_WINDOWS.txt" (
  copy /Y "%DIST%\README_WINDOWS.txt" "%OUT%\" >nul
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Compress-Archive -Path '%DIST%\bundle','%DIST%\instalar_medlink_connect.bat','%DIST%\README_WINDOWS.txt' -DestinationPath '%DIST%\MedLinkConnect_Windows_Portable.zip' -Force"
if errorlevel 1 (
  echo ADVERTENCIA: No se pudo crear el ZIP portable.
)

echo.
echo [5/5] Buscando Inno Setup para generar el instalador...
set "ISCC="
if exist "%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe" set "ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
if not defined ISCC if exist "%ProgramFiles%\Inno Setup 6\ISCC.exe" set "ISCC=%ProgramFiles%\Inno Setup 6\ISCC.exe"
if not defined ISCC for %%I in (iscc.exe) do if not "%%~$PATH:I"=="" set "ISCC=%%~$PATH:I"

if defined ISCC (
  "%ISCC%" "%ROOT%\windows\installer\inno_setup.iss"
  if exist "%ROOT%\build\windows\installer\MedLinkConnect-Setup.exe" (
    copy /Y "%ROOT%\build\windows\installer\MedLinkConnect-Setup.exe" "%DIST%\MedLinkConnect-Setup.exe" >nul
    echo Instalador creado: dist\Windows\MedLinkConnect-Setup.exe
  )
) else (
  echo ADVERTENCIA: Inno Setup no esta instalado; se omite el instalador .exe.
  echo Instala Inno Setup 6 y vuelve a ejecutar este script para generarlo.
)

echo.
echo ========================================================
echo   Compilacion completada. Artefactos en dist\Windows:
echo   - bundle\ (aplicacion)
echo   - MedLinkConnect_Windows_Portable.zip
echo   - MedLinkConnect-Setup.exe (si Inno Setup esta disponible)
echo ========================================================
popd >nul
if /I not "%CI%"=="true" pause
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
echo Instala Flutter y agrega su carpeta bin al PATH del sistema.
exit /b 1

:fail
echo.
echo ========================================================
echo   La compilacion fallo. Revisa el mensaje anterior.
echo ========================================================
popd >nul
if /I not "%CI%"=="true" pause
exit /b 1
