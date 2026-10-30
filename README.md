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
| **Linux** | Compilable / experimental | `flutter build linux --release` verificado. Wi-Fi nativo no implementado; rutas requieren `sudo`/polkit |
| **macOS** | RDP sobre red existente | Split tunnel no disponible: requiere helper privilegiado. Guía de compilación en `dist/macOS/` |
| **Android/iOS** | Experimental | Android requiere root para rutas; iOS requiere `NetworkExtension`. RDP se abre con un cliente externo |

En Windows la app genera perfiles Wi-Fi WPA2-PSK. Para redes WPA2-Enterprise o WPA3 debe existir un perfil previo en el sistema operativo.

## Requisitos (Windows)

- Windows con `mstsc.exe` disponible
- **Permisos de Administrador** (obligatorio para `route add`/`New-NetRoute`)
- Conexión a la red Wi-Fi del hospital

## Descargas

Los instaladores oficiales se publican en
[GitHub Releases](https://github.com/Nagamot-Byt/HAPPYCONNECTION/releases/latest):

- **Windows**: `MedLinkConnect-Setup.exe` (instalador 1 clic) o
  `MedLinkConnect_Windows_Portable.zip`.
- **Linux**: `MedLinkConnect_Linux_x64.run` (doble clic), `.deb` o `.tar.gz`.

## Instalación

### Linux

```bash
./scripts/build_linux.sh
./dist/Linux/MedLinkConnect_Linux_x64.run   # instalador 1 clic
# o: sudo apt install ./dist/Linux/medlink-connect_0.1.0_amd64.deb
```

### Windows

Doble clic en `scripts\build_windows.bat` o descarga el instalador desde
GitHub Releases. El instalador crea accesos directos normales y de
administrador en el escritorio y el menú de inicio.

## Compilación en 1 clic

Cada plataforma tiene un script que detecta Flutter, compila y deja los
artefactos listos en `dist/`:

| Plataforma | Comando / doble clic | Artefactos |
|---|---|---|
| Windows | `scripts\build_windows.bat` | bundle, ZIP portable, instalador Inno Setup |
| Linux | `./scripts/build_linux.sh` | `.run` autoejecutable, `.tar.gz`, `.deb` |
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
```

## Licencia

Propietario. Todos los derechos reservados.
