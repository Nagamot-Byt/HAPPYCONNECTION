@echo off
setlocal EnableExtensions
title Instalador MedLink Connect - Windows
pushd "%~dp0" >nul
color 0A
echo ========================================================
echo           Instalador 1-Click - MedLink Connect
echo ========================================================
echo.

if not exist "bundle\medlink_connect.exe" (
    echo ERROR: Falta la carpeta "bundle" con la aplicacion compilada.
    echo Ejecuta scripts\build_windows.bat para generarla.
    echo.
    pause
    popd >nul
    exit /b 1
)

set INSTALL_DIR=%LOCALAPPDATA%\MedLinkConnect

echo [1/4] Instalando archivos en %INSTALL_DIR%...
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
xcopy /E /Y /I "bundle\*" "%INSTALL_DIR%\" >nul
if exist "medlink_connect_admin.bat" (
    copy /Y "medlink_connect_admin.bat" "%INSTALL_DIR%\" >nul
)

echo [2/4] Creando acceso directo normal en el Escritorio...
call :make_shortcut "%INSTALL_DIR%\medlink_connect.exe" "%INSTALL_DIR%" "MedLink Connect"
if exist "%INSTALL_DIR%\medlink_connect_admin.bat" (
    echo [3/4] Creando acceso directo como Administrador...
    call :make_shortcut "%INSTALL_DIR%\medlink_connect_admin.bat" "%INSTALL_DIR%" "MedLink Connect (Administrador)"
) else (
    echo [3/4] Sin lanzador de Administrador; se omite el acceso directo.
)

echo [4/4] Creando accesos directos en el Menu Inicio...
set "START_MENU=%APPDATA%\Microsoft\Windows\Start Menu\Programs"
call :make_shortcut "%INSTALL_DIR%\medlink_connect.exe" "%INSTALL_DIR%" "MedLink Connect" "%START_MENU%"
if exist "%INSTALL_DIR%\medlink_connect_admin.bat" (
    call :make_shortcut "%INSTALL_DIR%\medlink_connect_admin.bat" "%INSTALL_DIR%" "MedLink Connect (Administrador)" "%START_MENU%"
)

echo.
echo ========================================================
echo   Instalacion completada con exito.
echo   Abre "MedLink Connect" desde tu Escritorio o Menu Inicio.
echo   Usa la version "(Administrador)" para el tunel dividido.
echo ========================================================
echo.
pause
popd >nul
exit /b 0

:make_shortcut
rem %1 = target, %2 = working dir, %3 = shortcut name, %4 = optional folder
set "TARGET=%~1"
set "WORKDIR=%~2"
set "NAME=%~3"
set "FOLDER=%~4"
if "%FOLDER%"=="" set "FOLDER=%USERPROFILE%\Desktop"
if not exist "%FOLDER%" set "FOLDER=%PUBLIC%\Desktop"
set "LINK=%FOLDER%\%NAME%.lnk"
set "VBS=%TEMP%\MedLinkShortcut_%RANDOM%.vbs"
> "%VBS%" echo Set oWS = WScript.CreateObject("WScript.Shell")
>> "%VBS%" echo Set oLink = oWS.CreateShortcut("%LINK%")
>> "%VBS%" echo oLink.TargetPath = "%TARGET%"
>> "%VBS%" echo oLink.WorkingDirectory = "%WORKDIR%"
>> "%VBS%" echo oLink.Save
cscript //Nologo "%VBS%" >nul
del "%VBS%" >nul 2>&1
exit /b 0
