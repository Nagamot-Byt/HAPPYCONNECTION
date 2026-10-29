@echo off
setlocal EnableExtensions
title MedLink Connect - Auditoria (1 clic)
pushd "%~dp0.." >nul

echo ========================================================
echo        MedLink Connect - Auditoria del proyecto
echo ========================================================
echo.

call :find_flutter
if errorlevel 1 goto :fail

echo [1/3] Verificando Flutter...
call flutter --version
if errorlevel 1 goto :fail

echo.
echo [2/3] Descargando dependencias y analizando...
call flutter pub get
if errorlevel 1 goto :fail
call flutter analyze lib test
if errorlevel 1 goto :fail

echo.
echo [3/3] Ejecutando pruebas...
call flutter test
if errorlevel 1 goto :fail

echo.
echo ========================================================
echo   Auditoria completada sin errores.
echo ========================================================
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
echo   La auditoria encontro errores. Revisa la salida anterior.
echo ========================================================
popd >nul
pause
exit /b 1
