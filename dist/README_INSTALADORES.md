# Instaladores MedLink Connect (1 link por sistema)

## Windows
**Archivo listo para distribución:** `dist/Windows/` (contiene instalador 1-clic + script Inno Setup)
- `instalar_medlink_connect.bat` - Copia a `%LOCALAPPDATA%\MedLinkConnect` y crea accesos directos
- `build_installer_inno.iss` - Genera `MedLinkConnect_Setup_Windows_v1.0.0.exe` con Inno Setup
- `README_WINDOWS.txt` - Instrucciones

**Para generar el bundle Windows:** En Windows ejecutar `flutter build windows --release` y copiar el contenido de `build\windows\x64\runner\Release\` a `dist\Windows\bundle\`. Después ejecutar el instalador o compilar con Inno Setup.

## Linux
**Ejecutable listo:** `dist/Linux/MedLinkConnect_Linux.tar.gz`
- Contiene `bundle/` (binario + libs + assets), `instalar_medlink_connect.sh`, `README_LINUX.txt`
- Instalación: extraer, ejecutar `./instalar_medlink_connect.sh`

## macOS
**Carpeta:** `dist/macOS/` contiene instalador y README. Generar bundle desde macOS con `flutter build macos --release` si se requiere.

## Notas
- Windows/Linux: flujo validado con túnel dividido, rutas, Wi-Fi y RDP
- Permisos de Administrador requeridos en Windows para modificar rutas
- Tests: 26 tests pasando
