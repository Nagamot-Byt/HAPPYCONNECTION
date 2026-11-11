# Auditoría de conectividad — MedLink Connect

- **Fecha:** 2026-11-10
- **Base analizada:** `b0dc96c` (`build/packages-dark-theme`), tras eliminar el
  campo manual de subredes y derivar rutas `/32` desde el host RDP.
- **Alcance:** cadena de conectividad completa (Wi-Fi → gateway/interfaz →
  túnel dividido → selección de servidor → verificación → DNS/ping/TCP →
  lanzamiento RDP → rollback) en Windows/Linux/Android/iOS/macOS, más
  integridad de código, pruebas y CI.
- **Método:** revisión estática dirigida de `ConnectionWorkflowService`,
  `HomeController`, `ServerPresetSelector`, plugins nativos Linux/Windows,
  manifiesto Windows, workflows de CI y suite de pruebas; ejecución de
  `flutter gen-l10n`, `flutter analyze`, `flutter test` (249/249) y
  `dart format`.

## 1. Resumen ejecutivo

La eliminación del campo de subredes simplifica la operación, pero deja al
descubierto una **regresión de orden en el flujo principal**: la
auto-selección del mejor servidor ocurre **antes** de instalar el túnel
dividido. En una red hospitalaria con DNS/resolución restringida, la
selección agota sus reintentos (hasta ~27 s) antes de que existan las rutas, y
puede fijar un host distinto del que luego se enruta.

Los hallazgos **P0** (5) afectan directamente la probabilidad de conectar en
Windows/Linux hospitalarios y deben corregirse antes del release. Los
hallazgos **P1** (10) son robustez, cobertura de plataforma y deuda técnica.

## 2. Hallazgos P0 (bloqueantes)

### P0-1. Auto-selección antes del túnel dividido

- **Ubicación:** `lib/core/connection_workflow_service.dart:271` (selección)
  vs. derivación de rutas `:298` y `enableSplitTunnel` `:353`;
  `lib/features/ui/server_preset_selector.dart:75`.
- **Problema:** `onSelectServer` se ejecuta antes de que existan las rutas
  `/32`. `diagnoseBest` sondea 5 presets × 3 intentos con esperas de hasta 9 s,
  llegando a ~27 s sin conectividad al hospital. Además el host elegido puede
  diferir del host cuyas rutas se instalaron.
- **Corrección:** resolver rutas `/32` de todos los presets candidatos,
  habilitar el túnel y **después** seleccionar el servidor; re-verificar rutas
  del host final antes del lanzamiento.

### P0-2. DNS antes de la ruta / DNS dividido

- **Ubicación:** `resolveHostCidrs` `:38`, ejecutado antes de las rutas `:301`.
- **Problema:** la resolución usa el resolver del sistema antes de que exista
  la ruta al DNS hospitalario. Si el DNS interno solo responde a través del
  gateway del hospital, la derivación `/32` falla y se conecta sin túnel o se
  aborta.
- **Corrección:** resolver con el DNS entregado por DHCP del Wi-Fi y, como
  respaldo, consultar directamente al gateway (`nslookup` con timeout corto:
  Windows `-timeout=2 -retry=1`, Linux/macOS `+timeout=2 +tries=1`). Emitir un
  mensaje accionable si no hay resolución.

### P0-3. Windows sin elevación aborta

- **Ubicación:** `windows/runner/runner.exe.manifest` (`asInvoker`, sin
  `requestedExecutionLevel`); `IsElevated` solo se comprueba al agregar rutas;
  `fallbackPlatforms` `:397` excluye Windows/Linux.
- **Problema:** si la app no se inicia como Administrador, agregar la ruta
  falla y el flujo aborta, aunque el RDP directo por TCP:3389 podría funcionar.
- **Corrección:** detectar falta de elevación, ofrecer relanzar con UAC y, si no
  es posible, continuar sin túnel cuando TCP:3389 sea alcanzable.

### P0-4. `conflicto_ruta` aborta en escritorio

- **Ubicación:** plugins de rutas nativos Linux/Windows.
- **Problema:** una ruta preexistente hacia el mismo destino se reporta como
  conflicto y aborta, aunque la ruta existente ya sea usable.
- **Corrección:** aceptar la ruta existente si apunta a la interfaz objetivo
  (Linux `route_exists_on_interface`, Windows `RouteExistsOnInterface` por
  LUID); en caso contrario, degradar sin túnel.

### P0-5. Multi-A / round-robin inconsistente

- **Ubicación:** `launchRdp` recibe el hostname, pero las rutas se calcularon
  con las IPs resueltas en el paso 3.
- **Problema:** si el nombre resuelve a varias IPs (balanceo/round-robin), el
  cliente RDP puede conectar a una IP sin ruta.
- **Corrección:** fijar la IP resuelta para el lanzamiento o re-resolver y
  asegurar rutas inmediatamente antes de lanzar.

## 3. Hallazgos P1 (no bloqueantes)

| # | Hallazgo | Ubicación |
|---|---|---|
| 6 | Sin timeout en canales de rutas (`pkexec` puede colgar) | `linux/runner/process_utils.cc:87-125` |
| 7 | Windows Wi-Fi cae a `discovery_unsecure`; sin `<nonBroadcast>` (SSID oculto); nombre de perfil = SSID | `windows/runner/wifi_manager_plugin.cc:538` |
| 8 | Linux solo `wpa-psk`; WPA3/802.1X requieren perfil existente | `linux/runner/wifi_manager_plugin.cc:358` |
| 9 | Latencia en el peor caso ~60 s (Wi-Fi 10 s + rutas + DNS + ping/TCP) | flujo completo |
| 10 | Android auto `/32` bloqueado por `_requiresNetworkConfig` aunque `_supportsRouteChanges` incluye Android | `home_controller.dart:72` |
| 11 | Gateway/interfaz obligatorios incluso para rutas on-link | `connection_workflow_service.dart:292` |
| 12 | Código muerto: `lib/mobile_rdp/`, `ios/Runner/RDP/RdpBridge.m` (fuera del proyecto Xcode), `native/bridge|freerdp` | varios |
| 13 | 18 `catch (_)` silenciosos sin trazabilidad | varios |
| 14 | Faltan pruebas: DNS-fallback, conflicto de ruta, selección post-túnel | `test/` |
| 15 | CI sin build Windows ni disparo en esta rama; README desactualizado (dice clave por argumento, el código usa `passwd-file`) | `.github/workflows/flutter_ci.yml`, `README.md:40-47` |

## 4. Plan de corrección

1. **P0-1/P0-5:** reordenar `onSelectServer` después del túnel; añadir
   `candidateHosts` a `connect()`; asegurar rutas del host final antes del
   lanzamiento.
2. **P0-2:** añadir `gatewayDnsResolver` inyectable con respaldo `nslookup` al
   gateway; mensaje accionable.
3. **P0-3/P0-4:** ampliar `fallbackPlatforms` a Windows/Linux para errores de
   privilegio/ruta y aceptar rutas existentes en la interfaz objetivo.
4. **P1:** timeouts en canales nativos, WPA3/802.1X, SSID oculto, limpieza de
   código muerto y ampliación de pruebas/CI.

## 5. Estado de verificación

- `flutter gen-l10n`: OK.
- `flutter analyze`: sin hallazgos.
- `flutter test`: 249/249.
- `dart format`: aplicado.
- CI: sin ejecución para `b0dc96c`; requiere PR manual a `master`.
