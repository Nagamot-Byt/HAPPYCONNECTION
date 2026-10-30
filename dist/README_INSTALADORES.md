# MedLink Connect — compilación y empaquetado en 1 clic

Los scripts de `scripts/` detectan Flutter, compilan y dejan artefactos listos
para usar en `dist/`. Los binarios generados no se versionan.

El workflow `.github/workflows/build-desktop.yml` compila Linux y Windows en CI
y publica los artefactos en GitHub Releases al crear un tag `v*`.

## Auditoría rápida

```bash
./scripts/audit.sh              # pub get + analyze + test
./scripts/audit.sh --build-linux
```

En Windows: doble clic en `scripts\audit.bat`.

## Windows

Doble clic en `scripts\build_windows.bat` (o ejecútalo desde `cmd`).

Genera en `dist\Windows\`:

- `bundle\` — aplicación compilada (`medlink_connect.exe`).
- `MedLinkConnect_Windows_Portable.zip` — paquete portable.
- `MedLinkConnect-Setup.exe` — instalador Inno Setup (si Inno Setup 6 está instalado).
- `instalar_medlink_connect.bat` — instalador 1 clic sin privilegios de sistema.
- `medlink_connect_admin.bat` — lanzador que solicita elevación (UAC).

Requisitos: Flutter con soporte Windows y Visual Studio C++ (Desktop development
with C++). Para el instalador `.exe`, Inno Setup 6.

## Linux

```bash
./scripts/build_linux.sh
```

Genera en `dist/Linux/`:

- `MedLinkConnect_Linux_<arch>.run` — instalador autoejecutable (doble clic).
- `MedLinkConnect_Linux_<arch>.tar.gz` — paquete portable.
- `medlink-connect_<version>_<arch>.deb` — paquete Debian/Ubuntu (si `dpkg-deb` existe).

Requisitos: Flutter con toolchain Linux (`clang`, `cmake`, `ninja`, `pkg-config`,
`libgtk-3-dev`, `libsecret-1-dev`).

## Android (mobile)

```bash
./scripts/build_android.sh
```

En Windows: doble clic en `scripts\build_android.bat`.

Genera en `dist/Android/`:

- `MedLinkConnect_<version>.apk` — instalar copiando al teléfono y abriéndolo.
- `MedLinkConnect_<version>.aab` — para Google Play.

Requisitos: Flutter + Android SDK + Java. La configuración actual firma release
con la clave de debug; para distribución real configura un keystore en
`android/key.properties`.

## iOS (mobile, solo macOS)

```bash
./scripts/build_ios.sh              # app sin firma
./scripts/build_ios.sh --simulator  # app para simulador
./scripts/build_ios.sh --ipa        # IPA firmada (requiere equipo/certificados)
```

Genera en `dist/iOS/` el `.zip` de la app o el `.ipa` firmado.

Requisitos: macOS con Xcode y CocoaPods.

## Mobile (ambas)

```bash
./scripts/build_mobile.sh
```

Compila Android y, si el host es macOS, también iOS.

## Notas operativas

- Windows: el túnel dividido requiere permisos de Administrador; usa el acceso
  directo “(Administrador)” o `medlink_connect_admin.bat`.
- Linux: las rutas requieren `sudo`/polkit; la app lo solicita cuando hace falta.
- macOS: el split tunnel requiere un helper privilegiado y no está disponible en
  esta compilación; la app continúa sobre las rutas del sistema.
- La suite automatizada se ejecuta con `flutter test` (60 pruebas).
