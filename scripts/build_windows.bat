@echo off
echo.
echo 🏥 HAPPYCONNECTION v2.0 - Compilador Windows
echo =============================================
echo.

echo Compilando backend Go...
cd backend
go build -o .\..\dist\happyconnection-backend.exe
if errorlevel 1 echo Error en compilación de Go
cd ..

echo.
echo Compilando app Flutter...
cd flutter
call flutter pub get
call flutter build windows --release
if errorlevel 1 echo Error en compilación de Flutter
cd ..

echo.
echo Copiando archivos...
mkdir dist\HAPPYCONNECTION
copy flutter\build\windows\x64\runner\Release\happyconnection.exe dist\HAPPYCONNECTION\
copy config\hospital_config.json dist\HAPPYCONNECTION\

echo.
echo ✅ Compilación completada
echo 📁 Ejecutable en: dist\HAPPYCONNECTION\happyconnection.exe
echo.
pause
