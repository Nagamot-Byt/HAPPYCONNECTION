# Instaladores MedLink Connect (1 link por sistema)

## Windows
**Archivo listo para distribución:** `dist/Windows/` (contiene instalador 1-clic + script Inno Setup)
- `instalar_medlink_connect.bat` - Copia a `%LOCALAPPDATA%\MedLinkConnect` y crea accesos directos
- `build_installer_inno.iss` - Genera `MedLinkConnect_Setup_Windows_v1.0.0.exe` con Inno Setup
- `README_WINDOWS.txt` - Instrucciones

**Para generar el bundle Windows:** En Windows ejecutar `flutter build windows --release` y copiar el contenido de `build\windows\x64\runner\Release\` a `dist\Windows\bundle\`. Después ejecutar el instalador o compilar con Inno Setup.

## Linux
**Referencia:** `dist/Linux/instalar_medlink_connect.sh` y `README_LINUX.txt`
- Generar el bundle con `flutter build linux --release`
- No se incluye un `.tar.gz` precompilado en este repositorio

## macOS
**Carpeta:** `dist/macOS/` contiene instalador y README. Generar bundle desde macOS con `flutter build macos --release` si se requiere.

## Notas
- Windows: flujo de túnel dividido, rutas y RDP implementado; requiere validación en un host Windows real
- Linux: build release verificado; Wi-Fi nativo pendiente y rutas requieren privilegios
- Permisos de Administrador requeridos en Windows para modificar rutas
- Tests: suite automatizada de Flutter (`flutter test`)
