# MedLink Connect

Aplicación de escritorio en Flutter para **Windows** (validado) que guía la conexión a una red hospitalaria, prepara el **túnel dividido por rutas estáticas** hacia subredes internas y abre la sesión **RDP** con el cliente nativo de Microsoft (`mstsc.exe`).

## Arquitectura (clave)

MedLink Connect **NO** implementa un túnel VPN completo (WireGuard/OpenVPN). Utiliza **rutas estáticas por subred (policy-based routing)**:

1. Conexión a la red Wi-Fi hospitalaria
2. Obtención de gateway e interfaz activa
3. Añadir rutas estáticas (`route add` / `New-NetRoute`) para las subredes hospitalarias configuradas
4. Verificación de rutas instaladas
5. Comprobación de alcance TCP:3389 al servidor RDP
6. Generación de `.rdp` optimizado y lanzamiento con `mstsc.exe`
7. **Rollback automático** si falla tras habilitar rutas

**Flujo end-to-end:** `Wi-Fi → Gateway/Interfaz → Rutas estáticas → TCP:3389 → Lanzamiento mstsc`

## Características

- **Wi-Fi**: Escaneo, conexión a redes abiertas o con clave, espera a conexión real con gateway/interfaz
- **Split-tunnel por rutas**: Solo el tráfico a subredes hospitalarias va por la interfaz hospitalaria
- **Detección robusta**: Gateway/interfaz vía `GetAdaptersAddresses`, PowerShell `Get-NetRoute`, `route print` o `GetIpForwardTable2`
- **RDP optimizado**: Perfiles `Adaptativo`, `Máxima estabilidad`, `Máxima velocidad` con generación dinámica `.rdp`
- **Diagnósticos**: Ping, TCP:3389, verificación de rutas, solucionador automático
- **Seguridad**: Rollback seguro por tracking LUID/prefijo, borrado solo de rutas con next-hop

## Plataformas

| Plataforma | Estado | Notas |
|---|---|---|
| **Windows** | Validado / Principal | Requiere **Ejecutar como Administrador** para modificar rutas estáticas |
| **Linux** | Funcional | Paquete `.deb` disponible en Releases. Algunas funciones Wi-Fi/nativas limitadas |
| **macOS** | Estructura disponible | Guía para compilar en Mac/GitHub Actions en `dist/macOS/` |
| **Android/iOS** | Experimental | Implementación parcial |

## Requisitos (Windows)

- Windows con `mstsc.exe` disponible
- **Permisos de Administrador** (obligatorio para `route add`/`New-NetRoute`)
- Conexión a la red Wi-Fi del hospital

## Instalación

### Linux (.deb)
```bash
sudo dpkg -i medlink-connect_1.0.0_amd64.deb
sudo apt install -f
```

### Linux (.tar.gz)
```bash
tar -xzf MedLinkConnect_Linux.tar.gz
cd Linux && ./instalar_medlink_connect.sh
```

### Windows
Ver `dist/Windows/README_WINDOWS.txt`. Generar bundle desde Windows con `flutter build windows --release` o usar Inno Setup (`build_installer_inno.iss`).

Los instaladores/binarios oficiales se publican en **GitHub Releases**.

## Desarrollo

```bash
flutter pub get
flutter run -d windows
flutter test
flutter analyze
dart format .
```

## Licencia

Propietario. Todos los derechos reservados.
