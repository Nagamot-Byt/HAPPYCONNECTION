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
| **Linux** | Compilable / experimental | Wi-Fi vía NetworkManager (`nmcli`); rutas requieren `sudo`/polkit |
| **macOS** | RDP sobre red existente / split tunnel no soportado | Requiere un helper privilegiado (`SMAppService`) que no forma parte de este release. Guía de compilación en `dist/macOS/` |
| **Android** | Compilable / experimental | APK y AAB release verificados con `targetSdk 36` (2026-10-30). Wi-Fi nativo no implementado: usar una red ya conectada; las rutas requieren root. RDP se abre con un cliente externo |
| **iOS** | RDP sobre red existente / split tunnel no soportado | Requiere `NetworkExtension` (`NEPacketTunnelProvider`) y entitlements de Personal VPN, fuera de este release |

En Windows la app genera perfiles Wi-Fi WPA2-PSK. En Linux usa NetworkManager (`nmcli`) y requiere que el servicio esté activo y el usuario tenga permiso para gestionar conexiones. Para redes WPA2-Enterprise o WPA3 debe existir un perfil previo en el sistema operativo.

## Seguridad y limitaciones

- Las credenciales RDP (`usuario` y `dominio`) se guardan cifradas con el
  almacén seguro del sistema. La contraseña Wi-Fi nunca se persiste.
- En Windows, la clave Wi-Fi se entrega a la API WLAN del sistema; Windows la
  conserva en el perfil de red administrado por el SO y MedLink Connect no la
  vuelve a leer.
- En Linux, la clave Wi-Fi se entrega a `nmcli` como argumento de proceso y no
  se persiste en la configuración de MedLink Connect.
- El diagnóstico usa como objetivo el host RDP configurado o, si no existe, el
  gateway de la red hospitalaria. No depende de `8.8.8.8` ni de Internet.
- `lib/mobile_rdp/` y `native/freerdp/` son un PoC aislado que no se importa en
  la aplicación y no forma parte de los instaladores de escritorio.
- macOS requiere un helper privilegiado para rutas; iOS requiere
  NetworkExtension. Sin ellos, el split tunnel no está soportado en esas
  plataformas.
- El escaneo y conexión Wi-Fi nativos están implementados en Windows y Linux
  (NetworkManager). En macOS, Android e iOS hay que partir de una red ya
  conectada.

## Requisitos (Windows)

- Windows con `mstsc.exe` disponible
- **Permisos de Administrador** (obligatorio para `route add`/`New-NetRoute`)
- Conexión a la red Wi-Fi del hospital

## Requisitos (Linux)

- NetworkManager activo con `nmcli` disponible para escanear y conectar Wi-Fi
- `sudo`/polkit para configurar las rutas del túnel dividido
- Cliente RDP compatible con `rdp://` (Remmina, FreeRDP o similar)

## Descargas

Los instaladores oficiales se publican en
[GitHub Releases](https://github.com/Nagamot-Byt/HAPPYCONNECTION/releases/latest):

- **Windows**: `dist/Windows/MedLinkConnect-Setup.exe` (instalador 1 clic) o
  `MedLinkConnect_Windows_Portable.zip`.
- **Linux**: `dist/Linux/MedLinkConnect_Linux_x64.run` (doble clic), `.deb` o
  `.tar.gz`.
- **macOS**: `dist/macOS/MedLinkConnect_macOS.dmg` (abrir y arrastrar la app a
  Aplicaciones).

## Instalación

### Linux

```bash
./scripts/build_linux.sh
./dist/Linux/MedLinkConnect_Linux_x64.run   # instalador 1 clic
# o: sudo apt install ./dist/Linux/medlink-connect_*_amd64.deb
```

### Windows

Doble clic en `scripts\build_windows.bat` o usa
`dist/Windows/MedLinkConnect-Setup.exe`. El instalador crea accesos directos
normales y de administrador en el escritorio y el menú de inicio.

### macOS

Abre `dist/macOS/MedLinkConnect_macOS.dmg`, arrastra `MedLink Connect.app` a
Aplicaciones y abre la aplicación. Si Gatekeeper la bloquea la primera vez,
haz clic derecho sobre la app y elige “Abrir”.

## Compilación en 1 clic

Cada plataforma tiene un script que detecta Flutter, compila y deja los
artefactos listos en `dist/`:

| Plataforma | Comando / doble clic | Artefactos |
|---|---|---|
| Windows | `scripts\build_windows.bat` | bundle, ZIP portable, instalador Inno Setup |
| Linux | `./scripts/build_linux.sh` | `.run` autoejecutable, `.tar.gz`, `.deb` |
| macOS | `./scripts/build_macos.sh` | DMG con la app universal |
| Android | `./scripts/build_android.sh` o `scripts\build_android.bat` | `.apk`, `.aab` |
| iOS (macOS) | `./scripts/build_ios.sh [--simulator\|--ipa]` | `.app.zip` o `.ipa` |
| Mobile | `./scripts/build_mobile.sh` | Android + iOS si el host es macOS |

El workflow `.github/workflows/build-desktop.yml` genera y publica los
artefactos de Linux y Windows en cada tag `v*`.

Auditoría repetible: `./scripts/audit.sh` (o `scripts\audit.bat`).

Detalles y requisitos por plataforma en `dist/README_INSTALADORES.md`.

## Documentación

- `CHANGELOG.md` — historial de versiones.
- `docs/audits/` — auditorías técnicas.
- `dist/README_INSTALADORES.md` — empaquetado por plataforma.

## Desarrollo

```bash
flutter pub get
flutter run -d windows
flutter test
flutter analyze
dart format .

# Integración con plugins nativos (Linux/Windows/macOS)
flutter test integration_test/app_integration_test.dart -d linux

# Pruebas opt-in contra red hospitalaria real
flutter test integration_test/live_network_test.dart -d <device> \
  --dart-define=RDP_TEST_HOST=10.0.0.10 \
  --dart-define=RDP_TEST_PORT=3389
```

## Licencia

Propietario. Todos los derechos reservados.
