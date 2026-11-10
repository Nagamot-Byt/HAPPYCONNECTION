# Auditoría de conectividad y estado del proyecto — MedLink Connect

- **Fecha:** 2026-11-09
- **Base analizada:** working tree sobre `1682b6e` (`build/packages-dark-theme`),
  previo al commit del bloque de verificación.
- **Alcance:** cadena de conectividad completa (Wi-Fi → gateway/interfaz →
  túnel dividido → verificación → DNS/ping/TCP → lanzamiento RDP → rollback) en
  Windows/Linux/Android/iOS/macOS, integridad del código, compatibilidad y
  estado general.
- **Método:** revisión estática dirigida de `HomeController`,
  `ConnectionWorkflowService`, diagnósticos y plugins nativos; ejecución de
  `flutter analyze`, suite completa con cobertura, pruebas de integración
  reales en Linux y build release Linux.
- **Calificación global: 834 / 1000.**

## 1. Resumen ejecutivo

La cadena de conectividad está **sólida y verificable en Windows y Linux**, que
son las plataformas objetivo del release: el flujo completa Wi-Fi nativo,
detección de gateway/interfaz, túnel dividido con pre-verificación y
verificación posterior, diagnóstico DNS/ping/TCP contra el host RDP real y
lanzamiento del cliente RDP, con rollback ante cualquier fallo y registro
persistente para limpiar rutas de sesiones anteriores. La suite creció a
**223 pruebas (93,2 % de cobertura de líneas)** y las pruebas de integración
Linux validan TCP real, lectura de rutas reales y escaneo Wi-Fi real.

Android opera en modo degradado documentado (sin root no hay túnel dividido,
pero la conexión RDP sobre la red existente sigue funcionando). iOS/macOS
declaran la limitación y continúan sin túnel. Las deudas conocidas son: build
Android no verificable en esta máquina (sin SDK), backend macOS de
`flutter_secure_storage` discontinuado (diferido al próximo ciclo) y
validación en hardware hospitalario real pendiente.

### Puntaje por área

| Área | Peso | Puntaje | Ratio |
|---|---:|---:|---:|
| Conectividad Windows (flujo principal) | 280 | 250 | 89 % |
| Conectividad Linux | 160 | 140 | 88 % |
| Conectividad Android | 110 | 70 | 64 % |
| Conectividad iOS/macOS (fallback) | 80 | 50 | 62 % |
| Diagnóstico, auto-selección y recuperación | 120 | 105 | 88 % |
| Integridad de código y pruebas | 170 | 157 | 92 % |
| Compatibilidad, build y CI | 80 | 62 | 78 % |
| **Total** | **1000** | **834** | **83,4 %** |

## 2. Cadena de conectividad por plataforma

### 2.1 Windows (250/280)

**Fortalezas**

- Flujo completo: WLAN API nativa (perfil por usuario con overwrite y
  reintentos `WLAN_PROFILE_USER`), confirmación del SSID objetivo con
  reintentos de 1 s hasta validar gateway/interfaz no vacíos, detección de
  ruta por defecto ignorando interfaces desconectadas.
- Túnel dividido con pre-verificación por subred, `enableSplitTunnel` nativo,
  espera de 600 ms y `verifyRoutes` con reintento de 800 ms en el nativo.
- Diagnóstico contra el host RDP real (no `8.8.8.8`): `InternetAddress.lookup`
  con timeout de 4 s, ping con causa de error visible (`lastProbeError`) y
  prueba TCP con límite global de ~9 s (máximo 4 s por dirección).
- Auto-selección de servidor por latencia TCP (`checkTcpPortDetailed`) con
  persistencia del elegido.
- `.rdp` optimizado por perfil y latencia medida (bpp, connection type,
  autoreconnect) y `.rdp` temporal borrado tras el lanzamiento.
- Rollback ante cualquier fallo posterior al túnel y limpieza de rutas
  pendientes registradas de sesiones previas.

**Deudas**

- Pendiente de validación en hardware hospitalario real (Wi-Fi del hospital,
  `mstsc` y elevación) tras los cambios de este bloque; el build Windows no
  corre en cada push (requiere tag o ejecución manual).

### 2.2 Linux (140/160)

**Fortalezas**

- Cadena de privilegios correcta y sin shell: root directo → `sudo -n` →
  `pkexec` (prompt gráfico polkit) con argv separado en `run_program`.
- Wi-Fi vía `nmcli` con contraseña en `passwd-file` temporal 0600 (nunca en
  `argv`) y perfil `medlink-<ssid>` como fallback.
- Verificación de rutas post-add, detección de conflictos sin borrar rutas
  ajenas y rechazo de `/0`.
- Pruebas de integración reales en Linux: arranque con plugins nativos, TCP
  contra socket local, lectura de rutas por el canal y escaneo/conexión Wi-Fi
  reales (3 pruebas correctas + 1 opt-in omitida).

**Deudas**

- El lanzamiento RDP depende del handler `rdp://`/`ms-rd-web://` registrado
  vía `xdg-open`; si no existe, `preLaunch` falla con mensaje claro (manejado,
  pero acopla la experiencia a la configuración del sistema).
- Tiempos fijos de espera (600 ms + reintento de 800 ms) no configurables.

### 2.3 Android (70/110)

**Fortalezas**

- Rutas solo se agregan/eliminan si existen comandos `su` validados y se
  rastrean por destino/gateway/interfaz; nunca borra rutas no creadas por la
  app; rechaza `/0` y corrige coincidencias `/32`.
- Ruta por defecto leída de `ConnectivityManager.activeNetwork` con fallback
  a transporte Wi-Fi; ping limitado a 2 s por intento.
- Fallback correcto sin root: `PrivilegeRequiredException` se captura, se
  revierte el intento de túnel y la conexión RDP continúa sobre la red
  existente (`rdp://` hacia cliente externo, p. ej. Microsoft RD).

**Deudas**

- Sin root (caso común) no hay túnel dividido: la app es un lanzador RDP con
  diagnóstico. Documentado, pero limita el valor en tablets no rooteadas.
- Sin canal `wifi_manager` en `MainActivity`: requiere red ya conectada por
  el sistema (decisión documentada).
- Ping vía `InetAddress.isReachable` puede usar eco TCP/7 y dar falsos
  negativos; la prueba TCP posterior compensa.

### 2.4 iOS/macOS (50/80)

**Fortalezas**

- Fallback explícito: `enableSplitTunnel` falla a propósito para activar la
  continuación sin túnel; `removeRoute`/`disableSplitTunnel` son no-op
  exitosos; errores claros (`requiere_network_extension` en iOS, helper
  privilegiado en macOS).
- macOS: diagnósticos con `Network.framework` (TCP 3389, 5 s) y ruta por
  defecto con `SCDynamicStore`; detección de cliente RDP con `NSWorkspace`.
- iOS: `AppDelegate` sin force-unwrap (corregido en auditoría previa).

**Deudas**

- Sin helper privilegiado macOS y sin NetworkExtension iOS no hay túnel
  dividido en absoluto (SEC-04/SEC-05 previos, fuera de alcance del release).

### 2.5 Diagnóstico, auto-selección y recuperación (105/120)

- `DefaultNetworkDiagnostics` expone `lastProbeError` (timeout,
  `diagnostics_not_available`, código de plataforma) y timeout Dart de 10 s
  por encima del peor caso nativo: evita falsos timeouts.
- El fallo de ping no aborta (solo registra error); el fallo de TCP sí aborta
  con rollback: correcto, TCP es el requisito real de RDP.
- Errores DNS registrados sin abortar (la prueba TCP es la decisiva).
- Al conectar a otra Wi-Fi se refrescan gateway/interfaz y se ignora la ruta
  por defecto de una interfaz distinta a la activa.
- El escaneo Wi-Fi fallido NO vacía la lista previa: puede mostrar SSIDs
  obsoletos (CON-08, menor).

## 3. Integridad del código y pruebas (157/170)

- `flutter analyze`: sin incidencias.
- **223 pruebas correctas** (unitarias + widgets); cobertura de líneas
  **93,2 %** (1813/1945), desde 65,8 %. Suites nuevas: `HomeController` (82),
  widgets de UI (25), `DefaultRouteManager` (21), `DefaultRdpLauncher` (15),
  `DefaultWifiManager` (11) con canales nativos mockeados.
- Integración Linux en verde (TCP real, rutas reales, Wi-Fi real) y build
  release Linux correcto.
- Sanitización en capas (Dart + nativo por plataforma) y sin inyección de
  comandos explotable (auditoría previa + revisión actual).
- Deudas: `HomeController` sigue siendo grande (~1100 líneas, ARQ-01 vigente);
  archivos por debajo del 85 %: `core/network_diagnostics` (33 %), `main`
  (69 %), `core/settings_storage` (74 %), `features/ui/home_screen` (78 %),
  `core/connection_workflow_service` (85 %).

## 4. Compatibilidad, build y CI (62/80)

- SDK/Dart `>=3.6.0 <4.0.0` y Flutter `>=3.27.0` alineados con el entorno
  (3.27.4) y con el uso de `Color.withValues`; Android `compileSdk 36`,
  `targetSdk 36`, `minSdk 21`, Java 11.
- `intl 0.19` y `flutter_lints 4` fijados correctamente por Flutter 3.27 (no
  upgradables en este ciclo).
- CI (GitHub Actions): analyze + test + integración Linux con xvfb; release
  Linux verificado localmente. Sin job de build Android en CI y sin SDK local:
  el APK/AAB deben validarse con `scripts/build_android.sh` en máquina con SDK.
- `flutter_secure_storage 9.2.4`: la rama macOS está discontinuada; 10.3.4 es
  resoluble pero cambia backends (Linux/macOS). **Decisión: diferir al próximo
  ciclo** con pruebas de migración de `FlutterSecureStorage`.
- PoC `lib/mobile_rdp` + submodule `native/freerdp` (79 MB, checkout local)
  siguen aislados por decisión ARQ-02; no forman parte de los instaladores.

## 5. Cambios aplicados en esta auditoría

| Cambio | Archivo | Motivo |
|---|---|---|
| Bridge nativo stub eliminado del APK | `android/app/src/main/cpp/`, `rdp/RdpBridge.kt`, `build.gradle.kts` | El `.so` `medlink_rdp_bridge` (stub que "finge" conexiones) se empaquetaba sin que nadie lo invocara; el PoC queda intacto en `lib/mobile_rdp` + `native/bridge` |
| TODO plantilla y `ndkVersion` retirados | `android/app/build.gradle.kts` | El `applicationId` ya es propio y ya no hay build nativo que requiera NDK |
| Artefactos `.cxx` eliminados | `android/app/.cxx/` | Basura de build de una ruta anterior del proyecto |
| Informe de auditoría | `docs/audits/AUDITORIA_2026-11-09.md` | Este documento |

## 6. Matriz de hallazgos

| ID | Severidad | Hallazgo | Evidencia | Estado |
|---|---|---|---|---|
| CON-01 | Media | Android sin túnel si no hay root | `MainActivity.kt` (su) | Diseño documentado + fallback RDP |
| CON-02 | Media | macOS sin helper privilegiado / iOS sin NetworkExtension | `MainFlutterWindow.swift`, `AppDelegate.swift` | Fuera de alcance del release (SEC-04/05) |
| CON-03 | Baja | Linux depende del handler `rdp://` del sistema | `linux/runner/rdp_launcher_plugin.cc` | Manejado con error claro |
| CON-04 | Baja | Tiempos fijos de verificación (600/800 ms) | workflow + `DefaultRouteManager` | Aceptable; no configurable |
| CON-05 | Baja | Escaneo Wi-Fi fallido no vacía la lista previa | `HomeController.refreshWifiNetworks` | **Corregido** (addendum) |
| CON-06 | Media | Sin validación de build Android en CI ni local | `.github/workflows/`, falta de SDK | **Corregido** (job `build-android`; hardware pendiente) |
| EST-01 | Media | Stub RDP nativo empaquetado sin uso | `android/app/src/main/cpp/` | **Corregido** en esta auditoría |
| EST-02 | Media | 41 archivos del bloque de verificación sin commit | `git status` | **Corregido**: commits de fix/build/test/docs |
| EST-03 | Media | Backend macOS de `flutter_secure_storage` discontinuado | `pubspec.lock` | **Corregido**: migrado a 10.3.4 (addendum) |
| EST-04 | Baja | `HomeController` monolítico | `home_controller.dart` | ARQ-01 vigente, mitigado parcialmente |
| EST-05 | Baja | Módulos bajo 85 % de cobertura | `lcov.info` | **Corregido**: 99,18 % global (addendum) |
| CMP-01 | Baja | `intl`/`flutter_lints` fijados por Flutter 3.27 | `pubspec.yaml` | Correcto; reconsiderar al migrar Flutter |

## 7. Plan de acción

### P0 — Cerrado en este bloque

1. Commit del bloque de verificación completo (fix + build + test + docs).
2. Eliminación del bridge nativo stub del APK.
3. Informe de auditoría de conectividad con calificación.

### P1 — Antes de un release formal

1. Build APK/AAB con `scripts/build_android.sh` en máquina con SDK Android
   (o job CI dedicado) para validar la eliminación del stub.
2. Validación en hardware hospitalario real: Wi-Fi del hospital, túnel con
   elevación en Windows, `sudo -n`/`pkexec` en Linux y `mstsc`/Remmina.
3. Migrar `flutter_secure_storage` a 10.x con pruebas de backend.

### P2 — Mejora continua

1. Job CI de build Android en cada push/PR.
2. Cobertura de `network_diagnostics`, `main`, `settings_storage`, `home_screen`.
3. Extraer más estado de `HomeController` (ARQ-01).
4. Evaluar bump de Flutter (desbloquearía `intl`/`flutter_lints`).


## 8. Addendum de mejoras (mismo día)

Tras cerrar la auditoría se aplicó el plan P1/P2 completo (salvo la decisión
estratégica de VpnService Android / helper macOS, que queda fuera de alcance):

| Mejora | Evidencia |
|---|---|
| CON-05: un escaneo Wi-Fi fallido vacía la lista de SSIDs | `HomeController.refreshWifiNetworks` + prueba `a failed rescan drops the previous SSID list` |
| Cobertura de los 5 módulos rezagados al 100 % | `main`, `network_diagnostics`, `settings_storage`, `home_screen`, `connection_workflow_service` |
| Suite de pruebas ampliada | 249 pruebas, cobertura de líneas **99,18 %** (5564/5610) |
| Migración `flutter_secure_storage` 9.2.4 → 10.3.4 | `pubspec.yaml`/`pubspec.lock`, backend `..._darwin`, sin `encryptedSharedPreferences` |
| CI Android con Java 17 y artefacto APK | `.github/workflows/flutter_ci.yml` (job `build-android`) |

### Re-calificación

| Área | Peso | Antes | Ahora |
|---|---:|---:|---:|
| Conectividad Windows (flujo principal) | 280 | 250 | 250 |
| Conectividad Linux | 160 | 140 | 140 |
| Conectividad Android | 110 | 70 | 74 |
| Conectividad iOS/macOS (fallback) | 80 | 50 | 50 |
| Diagnóstico, auto-selección y recuperación | 120 | 105 | 112 |
| Integridad de código y pruebas | 170 | 157 | 165 |
| Compatibilidad, build y CI | 80 | 62 | 72 |
| **Total** | **1000** | **834** | **863** |

**Calificación global actualizada: 863 / 1000 (86,3 %).**

Pendiente para superar 900: validación en hardware hospitalario real (Wi-Fi,
elevación Windows, `sudo -n`/`pkexec` Linux), build APK verificado en CI con
SDK real, y la decisión estratégica de túnel en Android (VpnService) / helper
privilegiado en macOS.
