# Despliegue y Compilación

## Windows - Generar .exe

```bash
cd flutter
flutter pub get
flutter build windows --release
```

El .exe estará en: `build/windows/x64/runner/Release/happyconnection.exe`

## macOS - Generar .app

```bash
cd flutter
flutter pub get
flutter build macos --release
```

El .app estará en: `build/macos/Build/Products/Release/happyconnection.app`

## Linux - Generar binario

```bash
cd flutter
flutter pub get
flutter build linux --release
```

El binario estará en: `build/linux/x64/release/bundle/happyconnection`

## iOS - Generar .ipa

```bash
cd flutter
flutter pub get
flutter build ios --release
```

## Android - Generar APK

```bash
cd flutter
flutter pub get
flutter build apk --release
```

## Backend Go

```bash
cd backend
go build -o happyconnection-backend
./happyconnection-backend
```

## Compilación con PyInstaller (Python antiguo)

```bash
pip install pyinstaller
pyinstaller --onefile --windowed app.py
```
