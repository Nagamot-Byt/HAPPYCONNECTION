@echo off
title Instalador MedLink Connect - Windows
color 0A
echo ========================================================
echo           Instalador 1-Click - MedLink Connect
echo ========================================================
echo.

set INSTALL_DIR=%LOCALAPPDATA%\MedLinkConnect

echo [1/3] Instalando archivos en %INSTALL_DIR%...
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
if exist "bundle" (
    xcopy /E /Y /I "bundle\*" "%INSTALL_DIR%\" >nul
) else (
    xcopy /E /Y /I "*.*" "%INSTALL_DIR%\" >nul
)

echo [2/3] Creando acceso directo en el Escritorio...
set SCRIPT="%TEMP%\CreateShortcut.vbs"
echo Set oWS = WScript.CreateObject("WScript.Shell") > %SCRIPT%
echo sLinkFile = oWS.SpecialFolders("Desktop") ^& "\MedLink Connect.lnk" >> %SCRIPT%
echo Set oLink = oWS.CreateShortcut(sLinkFile) >> %SCRIPT%
echo oLink.TargetPath = "%INSTALL_DIR%\medlink_connect.exe" >> %SCRIPT%
echo oLink.WorkingDirectory = "%INSTALL_DIR%" >> %SCRIPT%
echo oLink.Save >> %SCRIPT%
cscript //Nologo %SCRIPT%
del %SCRIPT%

echo [3/3] Creando acceso directo en el Menu Inicio...
set START_MENU=%APPDATA%\Microsoft\Windows\Start Menu\Programs
set SCRIPT_MENU="%TEMP%\CreateMenuShortcut.vbs"
echo Set oWS = WScript.CreateObject("WScript.Shell") > %SCRIPT_MENU%
echo sLinkFile = "%START_MENU%\MedLink Connect.lnk" >> %SCRIPT_MENU%
echo Set oLink = oWS.CreateShortcut(sLinkFile) >> %SCRIPT_MENU%
echo oLink.TargetPath = "%INSTALL_DIR%\medlink_connect.exe" >> %SCRIPT_MENU%
echo oLink.WorkingDirectory = "%INSTALL_DIR%" >> %SCRIPT_MENU%
echo oLink.Save >> %SCRIPT_MENU%
cscript //Nologo %SCRIPT_MENU%
del %SCRIPT_MENU%

echo.
echo ========================================================
echo   ^!Instalacion completada con exito^!
echo   Ya puedes abrir "MedLink Connect" desde tu Escritorio.
echo ========================================================
echo.
pause
