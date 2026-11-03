# MedLink Connect — instaladores de escritorio

Versión `0.1.0`. Artefactos generados desde el commit `4ce6ac2`.

Cada plataforma tiene su propia carpeta con un instalador de un solo clic y un
README específico.

## Linux — `dist/Linux/`

| Archivo | Uso |
| --- | --- |
| `MedLinkConnect_Linux_x64.run` | Instalador de un solo clic. Doble clic, sin `sudo`. |
| `medlink-connect_0.1.0_amd64.deb` | Instalación para Debian/Ubuntu: `sudo apt install ./medlink-connect_*_amd64.deb`. |
| `MedLinkConnect_Linux_x64.tar.gz` | Versión portable: extraer y ejecutar `instalar_medlink_connect.sh`. |
| `README_LINUX.txt` | Instrucciones y solución de problemas. |

Si el `.run` se descargó por navegador y no se abre:

```bash
chmod +x MedLinkConnect_Linux_x64.run
./MedLinkConnect_Linux_x64.run
```

No lo ejecutes con `sudo` ni como root. El instalador copia la aplicación a
`~/.local/share/medlink_connect` y crea los accesos del menú y del escritorio.

## Windows — `dist/Windows/`

| Archivo | Uso |
| --- | --- |
| `MedLinkConnect-Setup.exe` | Instalador de un solo clic (Inno Setup). |
| `MedLinkConnect_Windows_Portable.zip` | Versión portable con instalador `.bat` sin privilegios. |
| `README_WINDOWS.txt` | Instrucciones, modo administrador y requisitos. |

Doble clic en `MedLinkConnect-Setup.exe`. Si SmartScreen muestra una advertencia,
elige “Más información” > “Ejecutar de todas formas”. El instalador es unsigned.

## macOS — `dist/macOS/`

| Archivo | Uso |
| --- | --- |
| `MedLinkConnect-macOS-Installer.command` | Instalador de un solo clic. Instala en `/Applications` y abre la app. |
| `MedLinkConnect_macOS_Installer.zip` | El mismo instalador comprimido, conservando el permiso de ejecución. |
| `MedLinkConnect_macOS_Portable.zip` | Aplicación `.app` universal para arrastrar a `/Applications`. |
| `README_MACOS.txt` | Instrucciones y advertencias de Gatekeeper. |

Usa el ZIP del instalador si el archivo `.command` perdió el permiso de
ejecución al transferirse. La aplicación soporta Intel (x86_64) y Apple Silicon
(arm64), requiere macOS 10.14 o posterior y no está notarizada por Apple.

## Integridad

`SHA256SUMS.txt` contiene los hashes de los instaladores principales. Verifica
con:

```bash
sha256sum -c SHA256SUMS.txt
```

En macOS: `shasum -a 256 -c SHA256SUMS.txt`.

## Recompilar

- Linux: `./scripts/build_linux.sh`
- Windows: `scripts\build_windows.bat` en Windows con Flutter, Visual Studio C++
  e Inno Setup 6.
- macOS: `flutter build macos --release` en macOS y empaquetar el `.app`.

El workflow `.github/workflows/build-desktop.yml` compila Linux y Windows en CI.
El workflow `.github/workflows/build-apple.yml` compila macOS en un runner Apple.
