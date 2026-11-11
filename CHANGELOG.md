# Changelog

Todas las versiones relevantes de MedLink Connect.

## [Sin publicar] - 2026-11-09

### Añadido

- Pruebas de integración con `integration_test`:
  - arranque real de la app con los plugins nativos registrados;
  - conexión TCP real contra un socket local mediante el canal de diagnóstico;
  - lectura real de interfaces y ruta por defecto mediante el canal de rutas.
- Pruebas de integración opt-in para red hospitalaria real:
  `RDP_TEST_HOST`, `RDP_TEST_PORT`, `EXPECT_WIFI`, `ROUTE_TEST_CIDR`,
  `ROUTE_TEST_GATEWAY` y `ROUTE_TEST_INTERFACE`.
- Firmado de release Android mediante `android/key.properties` (plantilla en
  `android/key.properties.example`); si falta el archivo se usa la clave de
  depuración para builds locales.
- Auditoría de conectividad y estado del proyecto con calificación 834/1000:
  `docs/audits/AUDITORIA_2026-11-09.md`.
- Job `build-android` en CI (Java 17 + Flutter 3.27.4) que compila
  `flutter build apk --release` y publica el APK como artefacto, para validar
  Android en cada push/PR sin depender de un SDK local.
- Suite ampliada a 249 pruebas: cubre el arranque `main()`, el flujo completo
  de pasos del workflow, el diálogo de restablecer ajustes, fallos de
  DNS/ICMP/TCP con causa, selección de servidor con error, cliente/manejador
  RDP ausente, Wi-Fi que nunca confirma, fallback de gateway y
  `checkTcpPortDetailed`.

### Cambiado

- Túnel dividido sin configuración manual: se eliminó el campo «Subredes del
  hospital». Ahora la app resuelve el servidor RDP (preset o IP) y crea rutas
  `/32` automáticas vía el gateway hospitalario; si la resolución falla,
  continúa sin túnel. La verificación de rutas del solucionador también usa
  esas rutas automáticas.
- ARQ-01: el estado y la lógica Wi-Fi de `HomeController` se extrajeron a
  `WifiConnectionCoordinator` (escaneo de SSIDs, conexión actual, confirmación
  del SSID objetivo y resolución de la selección) y la selección de presets de
  servidor a `ServerPresetSelector` (catálogo hospitalario, aplicación y
  diagnóstico de latencia TCP con reintentos). La API pública del controlador
  no cambia y este pasa de 1380 a 1190 líneas.
- `flutter_secure_storage` migrado de 9.2.4 a 10.3.4: el backend macOS pasa a
  `flutter_secure_storage_darwin` (el paquete `..._macos` está discontinuado) y
  se retira `encryptedSharedPreferences` (obsoleto en Android). La API de
  `SettingsStorage` no cambia.

### Eliminado

- Bridge nativo stub `medlink_rdp_bridge` (`jni_bridge.cpp`,
  `engine_bridge.c`, `RdpBridge.kt`) ya no se empaqueta en el APK Android: nada
  lo invocaba y su stub simulaba conexiones RDP. El PoC aislado
  (`lib/mobile_rdp`, `native/bridge`, submodule `native/freerdp`) queda
  intacto y fuera de los instaladores.
- `ndkVersion` y TODO de plantilla retirados de `android/app/build.gradle.kts`
  al desaparecer el único build nativo de la app.

### Corregido

- La auto-selección del mejor servidor ahora ocurre después de instalar el
  túnel dividido: se pre-enrutan las rutas `/32` de todos los presets
  candidatos y, tras elegir, se aseguran las rutas del host final antes de
  lanzar RDP (P0-1/P0-5).
- Si el resolver del sistema falla antes de que exista la ruta, las rutas `/32`
  se resuelven consultando directamente el gateway hospitalario con `nslookup`
  (timeout corto en Windows/Linux/macOS) (P0-2).
- Windows y Linux ya no abortan por falta de elevación o por una ruta
  preexistente: continúan con RDP directo si el servidor responde en TCP, y los
  gestores de rutas aceptan una ruta existente en la interfaz objetivo
  (P0-3/P0-4).
- Un escaneo Wi-Fi fallido ya no deja SSIDs obsoletos en la lista: el estado se
  vacía y la UI no ofrece redes que podrían no existir (CON-05).
- El fallback sin túnel dividido en Android ahora captura
  `PrivilegeRequiredException` (falta de root) y continúa con RDP sobre la red
  existente en lugar de abortar.
- `InputSanitizer.sanitizeCidr` canonicaliza la dirección de red y rechaza
  prefijos `/0`; se evita agregar rutas por defecto desde la aplicación.
- `ConnectionWorkflowService` refresca gateway/interfaz tras conectar a otra
  Wi-Fi, ignora rutas por defecto de interfaces que no son la Wi-Fi activa y no
  exige gateway/interfaz en iOS/macOS.
- `HomeController` conserva el gateway guardado al iniciar, omite la gestión
  Wi-Fi en plataformas sin canal nativo y no intenta limpiar rutas en iOS/macOS.
- Windows: perfiles WLAN se escriben con overwrite y reintento
  `WLAN_PROFILE_USER`; se eliminan conflictos de rutas tracked/misma interfaz,
  se evita exigir elevación cuando no hay nada que borrar y se ignoran
  interfaces desconectadas en la ruta por defecto.
- Linux: la contraseña Wi-Fi ya no viaja en `argv`; se usa `passwd-file` temporal
  (0600) con `nmcli connection up` y perfil `medlink-<ssid>` como fallback. Las
  rutas validan conflictos sin borrar rutas ajenas y rechazan `/0`.
- Android: se rastrean rutas por destino/gateway/interfaz, se evita borrar rutas
  no creadas por la app, se rechaza `/0`, se corrigen coincidencias `/32` y la
  ruta por defecto usa `activeNetwork` antes de recurrir a Wi-Fi; ping se limita
  a 2 s por intento.
- iOS/macOS: `removeRoute` y `disableSplitTunnel` son no-op exitoso,
  `verifyRoutes` devuelve lista vacía y `enableSplitTunnel` sigue fallando para
  activar el fallback.
- macOS: diagnósticos con `Network.framework` (TCP 3389, 5 s) y lectura de la
  ruta por defecto con `SCDynamicStore`; detección de cliente RDP con
  `NSWorkspace` sin depender de `osascript`.
- Los timeouts de diagnóstico TCP usan un límite global de ~9 s con máximo 4 s
  por dirección; ping se limita a 2 s por intento.
- Las subredes vacías ya no bloquean Android, iOS ni macOS; el host RDP puede
  quedar vacío si se autoselecciona un preset, y gateway/interfaz solo se exigen
  en Windows/Linux. La UI oculta el selector de perfil RDP y los controles Wi-Fi
  en plataformas sin soporte nativo.
- El workflow pre-verifica cada subred antes de habilitar el túnel y solo
  persiste para limpieza las rutas que realmente faltaban; un fallo de
  verificación no registra rutas ajenas. Las subredes se deduplican antes de
  llegar a la capa nativa.
- Windows: agregar rutas ya no elimina rutas externas para el mismo destino; si
  existe una ruta ajena se devuelve `conflicto_ruta`. La gestión WLAN detecta
  seguridad open/WEP/enterprise/PSK/SAE, no sobrescribe perfiles empresariales y
  solo crea perfiles abiertos cuando corresponde.
- Disponibilidad y lanzamiento RDP coherentes en Windows, Linux, iOS y macOS:
  se comprueban handlers/URI reales con fallback `ms-rd-web://`, se captura
  `MissingPluginException` y el perfil RDP solo se envía en Windows.
- Diagnóstico: `NetworkProbeResult` y `checkTcpPortDetailed` asocian cada causa
  de fallo a su sonda, evitando carreras entre presets; el troubleshooter deja
  de atribuir fallos TCP a ping.
- `InputSanitizer.sanitizeHostname` valida etiquetas DNS (sin puntos
  consecutivos, guiones en extremos ni nombres de más de 253 caracteres) y
  `SettingsStorage.init()` tolera fallos individuales de secure storage.

### Cambiado

- Mensajes y errores de `ConnectionWorkflowService` localizados es/en; el
  servicio recibe `AppLocalizations` desde el controlador.
- `HomeController` delega presets/logs en `home_models.dart` y la clasificación
  de errores en `error_guidance.dart`.
- Android `compileSdk`/`targetSdk` actualizados a 36.
- README declara explícitamente macOS/iOS sin split tunnel en este release.

### Verificación

- `flutter analyze lib test integration_test`: sin incidencias.
- `flutter test`: 249 pruebas correctas (unitarias y de widget) con Flutter
  3.27.4 / Dart 3.6.2.
- Cobertura de líneas (alcance `lib`, convención de auditorías previas):
  97,64 % (1900/1946) tras el bloque de verificación y 97,69 % (1949/1995)
  tras el refactor ARQ-01; el 99,18 % (5564/5610) citado en el addendum
  anterior usaba un alcance no reproducible bajo esta convención y se retira.
- Suites: `HomeController` (82), widgets de UI (25),
  `DefaultRouteManager` (21), `DefaultRdpLauncher` (15) y `DefaultWifiManager`
  (11) con los canales nativos mockeados vía `TestDefaultBinaryMessengerBinding`.
- `flutter test integration_test/app_integration_test.dart -d linux`: 3
  pruebas correctas (arranque, TCP local y lectura de rutas) y 1 opt-in
  omitida sin variables de red hospitalaria.
- Builds release Linux, APK Android y AAB Android correctos; APK con
  `minSdk 21`, `targetSdk 36` y `compileSdk 36`.
- Pendiente de validación externa: Wi-Fi/root/rutas/RDP en hardware real y CI
  Windows/macOS/iOS con los cambios publicados.

## [0.1.0] - 2026-10-30

Primera versión publicable con empaquetado de escritorio para Windows y Linux.

### Añadido

- Flujo guiado Wi-Fi → gateway/interfaz → rutas estáticas → TCP:3389 → RDP.
- Diagnóstico de red y rutas, perfiles RDP adaptativos y rollback automático.
- Internacionalización completa español/inglés de interfaz, guías y registros.
- Empaquetado de escritorio en un clic:
  - Windows: bundle, ZIP portable e instalador Inno Setup.
  - Linux: instalador autoejecutable `.run`, `.tar.gz` portable y `.deb`.
- Pipeline de GitHub Actions para generar artefactos de Linux y Windows y
  publicarlos en GitHub Releases al crear un tag `v*`.
- Accesos directos de escritorio y menú de aplicaciones en ambos instaladores.
- Logs estructurados con nivel de error explícito (sin emojis) y semántica de
  accesibilidad para estado, pasos y registros.
- Tema claro/oscuro aplicado también al fondo de la aplicación.

### Cambiado

- Documentación reorganizada: auditoría en `docs/audits/` y notas de release
  consolidadas en este changelog.
- README actualizado con instalación, compilación en un clic y enlaces de
  descarga.

### Corregido

- Hallazgos de la auditoría ToT 2026-10-29, incluido UI-01 (localización).
- Flujo de conexión endurecido con validaciones y limpieza segura de rutas.
- Clasificación de errores mediante tipos (`MedLinkErrorType`) en lugar de
  comparar texto o emojis.
- Diagnóstico dirigido al host RDP o gateway, con la causa real de fallo visible
  en el registro.
- Validación estricta de interfaces en Android y eliminación del force-unwrap
  del motor Flutter en iOS.
- Build de Windows en cada push/PR al ejecutar el pipeline de escritorio.
- Build Android reparado: el módulo `app` ahora aplica los plugins de Android,
  Kotlin y Flutter Gradle, y el NDK queda alineado con las dependencias
  (`27.0.12077973`).
- Rutas Android endurecidas: lectura de shell sin bloqueo, timeout de 20 s,
  seguimiento sincronizado de rutas, rollback exacto por `via`/`dev`,
  verificación con parseo estricto y errores de `flush/clear` ya no silenciosos.
- Linux: `pkexec` solo se usa como fallback ante fallos de privilegios, y
  `flushDns` devuelve error si todas las estrategias fallan.
- Controlador: notificaciones protegidas tras `dispose`, reset abortado si no
  se pueden retirar rutas previas, SSID vacío persistido explícitamente,
  deduplicación de redes y diagnóstico con gateway/interfaz recién sincronizados.
- El túnel ya no se marca inactivo cuando el rollback de rutas falla.
- `DefaultRouteManager.verifyRoutes` valida subredes, gateway e interfaz antes
  del canal nativo.
- Apple CI actualizado a `macos-15`; `pod install` ya no oculta fallos.

### Verificación

- `flutter analyze lib test`: sin incidencias.
- `flutter test --coverage`: 67 pruebas correctas; cobertura de líneas 63,3 %
  (1072/1694).
- Build Linux release validado localmente.
- Build Windows e instalador generados por CI.
- Build Android validado localmente: APK debug, APK release y AAB release, con
  artefactos en `dist/Android/` (firma de depuración).
