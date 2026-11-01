# Changelog

Todas las versiones relevantes de MedLink Connect.

## [Sin publicar] - 2026-10-30

### Añadido

- Pruebas de integración con `integration_test`:
  - arranque real de la app con los plugins nativos registrados;
  - conexión TCP real contra un socket local mediante el canal de diagnóstico;
  - lectura real de interfaces y ruta por defecto mediante el canal de rutas.
- Pruebas de integración opt-in para red hospitalaria real:
  `RDP_TEST_HOST`, `RDP_TEST_PORT`, `EXPECT_WIFI`, `ROUTE_TEST_CIDR`,
  `ROUTE_TEST_GATEWAY` y `ROUTE_TEST_INTERFACE`.

### Cambiado

- Mensajes y errores de `ConnectionWorkflowService` localizados es/en; el
  servicio recibe `AppLocalizations` desde el controlador.
- `HomeController` delega presets/logs en `home_models.dart` y la clasificación
  de errores en `error_guidance.dart`.
- Android `compileSdk`/`targetSdk` actualizados a 36.
- README declara explícitamente macOS/iOS sin split tunnel en este release.

### Verificación

- `flutter analyze lib test integration_test`: sin incidencias.
- `flutter test --coverage`: 75 pruebas correctas; cobertura de líneas 64,8 %
  (1132/1747).
- `flutter test integration_test/app_integration_test.dart -d linux`: 3 pruebas
  de integración correctas.
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
