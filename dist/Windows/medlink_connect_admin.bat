@echo off
setlocal
set "EXE=%~dp0medlink_connect.exe"
if not exist "%EXE%" (
  echo ERROR: No se encontro medlink_connect.exe junto a este lanzador.
  pause
  exit /b 1
)
net session >nul 2>&1
if %errorlevel%==0 (
  start "" "%EXE%"
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%EXE%' -Verb RunAs"
)
exit /b 0
