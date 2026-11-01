# Auditoría integral ToT — MedLink Connect

- **Fecha:** 2026-10-29
- **Base analizada:** `d30321b` (`master`)
- **Alcance:** `lib/`, `test/`, plugins nativos Windows/Linux/Android/iOS/macOS, scripts, CI y documentación de release.
- **Método:** revisión estática dirigida, ejecución de `flutter analyze`, suite de pruebas con cobertura y verificación del estado de CI.
- **Límite:** no hubo ejecución interactiva en Windows ni compilación local Apple en esta sesión. La validación runtime de red/RDP queda sujeta a prueba en equipo hospitalario y a los workflows nativos.

## 1. Resumen ejecutivo

El flujo principal de Windows está bien estructurado: Wi-Fi → gateway/interfaz → túnel dividido → verificación de rutas → prueba TCP → generación `.rdp` → `mstsc`, con rollback y limpieza de rutas pendientes. No se encontró una inyección de comandos explotable: las rutas se validan en Dart y se ejecutan con APIs nativas o argumentos separados en las plataformas relevantes.

El producto **no está listo para declararse multiplataforma completo**. Windows es la plataforma principal; macOS no tiene split tunnel operativo, iOS requiere NetworkExtension y el scaffolding RDP móvil no está conectado a la UI. La calidad de release depende además de cerrar brechas de i18n, accesibilidad y cobertura de pruebas.

### Cambios correctivos aplicados en esta auditoría

| Cambio | Archivo | Motivo |
|---|---|---|
| Piso de SDK/Flutter alineado con `Color.withValues` | `pubspec.yaml` | Evita builds fallidos en Flutter < 3.27. |
| Estado del túnel solo se activa tras confirmación nativa | `lib/features/ui/home_controller.dart` | Antes se marcaba activo al iniciar el paso, incluso si fallaba. |
| Persistencia tras selección automática de servidor | `lib/features/ui/home_controller.dart` | El host elegido por diagnóstico no se guardaba. |
| Limpieza de contraseña Wi-Fi en `connectWifiOnly` | `lib/features/ui/home_controller.dart` | Reduce retención de secreto en memoria/UI. |
| Límite de 500 entradas y autoscroll en logs | `home_controller.dart`, `connection_logs_widget.dart` | Evita crecimiento sin límite y mejora lectura del evento reciente. |
| Puerto RDP inválido deja de ser silencioso | `lib/features/ui/home_controller.dart` | Registra el fallback a 3389 para que el usuario lo vea. |
| `coverage/` ignorado por Git | `.gitignore` | Evita commitear artefactos de cobertura. |

## 2. Árbol ToT

Pregunta raíz: **¿Es seguro y confiable desplegar MedLink Connect en el hospital?**

```
¿Release confiable?
├─ Seguridad y privilegios
│  ├─ Inyección en rutas/SSID/RDP
│  ├─ Manejo de credenciales y secretos
│  └─ Modelo de privilegios por plataforma
├─ Arquitectura y mantenibilidad
│  ├─ Separación core/UI/nativo
│  ├─ Tamaño y responsabilidades del controlador
│  └─ Acoplamientos y código muerto
├─ Funcionalidad y confiabilidad
│  ├─ Flujo Wi-Fi → rutas → TCP → RDP
│  ├─ Rollback y limpieza tras fallo
│  ├─ Persistencia de configuración
│  └─ Diagnóstico y recuperación
├─ UI/UX e integridad
│  ├─ i18n es/en
│  ├─ Tema claro/oscuro
│  ├─ Accesibilidad y semántica
│  └─ Feedback, logs y estados
├─ Build, CI y release
│  ├─ Matriz de plataformas
│  ├─ Triggers de workflows
│  └─ Artefactos e instaladores
└─ Pruebas y observabilidad
   ├─ Cobertura por módulo
   ├─ Casos de fallo/rollback
   └─ Trazabilidad de errores
```

## 3. Evaluación por rama

### 3.1 Seguridad y privilegios

**Fortalezas**

- `InputSanitizer` valida IPv4, CIDR, hostname, puerto y credenciales RDP.
- Windows usa APIs nativas para rutas y Wi-Fi; Linux usa `g_spawn_sync` con argv; macOS usa regex estricta antes de `route`; Android valida interfaz con `^[A-Za-z0-9_.:-]+$`.
- El `.rdp` temporal de Windows contiene usuario/dominio, **no contraseña**, y se elimina al cerrar `mstsc`; además hay limpieza de archivos obsoletos.
- Usuario y dominio RDP se guardan en `FlutterSecureStorage` (DPAPI en Windows).

**Riesgos**

- El sanitizador Dart de interfaz acepta caracteres que los validadores nativos estrictos rechazan (`'`, `;`, etc.). Hoy no es explotable porque no se interpola en shell en las plataformas analizadas, pero la defensa en profundidad es inconsistente.
- La contraseña Wi-Fi no se guarda en la app, pero Windows conserva el perfil WLAN con su clave. Debe documentarse como comportamiento esperado del sistema.
- macOS no tiene helper privilegiado (`SMAppService`); los métodos de rutas están deliberadamente bloqueados. El split tunnel macOS no es funcional.
- iOS no puede modificar rutas sin NetworkExtension; las llamadas devuelven `requiere_network_extension`.
- `ios/Runner/AppDelegate.swift` registra canales usando `vc.engine!`; conviene eliminar el force-unwrap para evitar crash si el engine no está listo.

**Veredicto:** sin crítico de inyección explotable; deuda alta en privilegios macOS y en consistencia de validación.

### 3.2 Arquitectura y mantenibilidad

**Fortalezas**

- Interfaces claras: `RouteManager`, `WifiManager`, `NetworkDiagnostics`, `RdpLauncher`, `SettingsStorage`.
- `ConnectionWorkflowService` concentra el flujo y permite probar rollback con mocks.
- Inyección de dependencias con `injectable/get_it`.

**Riesgos**

- `HomeController` tiene ~1158 líneas y mezcla estado de UI, persistencia, diagnóstico, selección de servidor y coordinación del flujo. Es el principal punto de complejidad y testabilidad.
- Presets de servidores hardcodeados en el controlador; deberían venir de configuración o almacenamiento.
- `lib/mobile_rdp/` es un PoC desconectado de la app, con proxy en memoria; genera expectativa de funcionalidad que no existe.
- Varias claves ARB existen pero no se usan; la localización está a medio integrar.
- macOS mantiene ramas de rutas inalcanzables por el bloqueo de `privilegedMethods`.

**Veredicto:** arquitectura comprensible y modular en el core, pero el controlador es un monolito que concentra el riesgo de regresión.

### 3.3 Funcionalidad y confiabilidad

**Fortalezas**

- Rollback del túnel ante error y registro persistente para limpiar rutas de una sesión anterior.
- Reintentos TCP y verificación de rutas posterior a la creación.
- Confirmación de SSID objetivo en vez de confiar solo en la respuesta de conexión.
- Diagnóstico de gateway/interfaz y fallback a ruta por defecto.

**Hallazgos**

- **Corregido:** `splitTunnelActive` se activaba al emitir el paso `splitTunnel`, antes de que el nativo confirmara. Ahora se activa en `onSplitTunnelEnabled` y se limpia en unavailable/rollback/error.
- **Corregido:** el servidor elegido automáticamente no se persistía. Ahora se guarda al completar la conexión.
- **Corregido:** `connectWifiOnly` dejaba la contraseña en el controlador. Ahora se limpia en `finally`.
- **Corregido:** un puerto RDP inválido caía silenciosamente a 3389. Ahora se registra el fallback.
- `runDiagnostics` hace ping a `8.8.8.8`. En una red hospitalaria restringida esto puede fallar aunque el servidor RDP sea alcanzable; además confunde “Internet” con “red del hospital”.
- `DefaultNetworkDiagnostics` captura cualquier excepción y devuelve `null`; no distingue timeout, plugin ausente y host inalcanzable.
- `setErrorGuidance` clasifica errores por subcadenas de texto en español. Es frágil ante cambios de mensaje, idioma o plataforma.
- `saveSettings` solo persiste Wi-Fi si el SSID resuelto no está vacío; no hay una ruta explícita para borrar el SSID guardado.

**Veredicto:** el flujo de Windows es razonablemente robusto, pero el diagnóstico y la clasificación de errores necesitan códigos estructurados, no strings.

### 3.4 UI/UX e integridad

**Fortalezas**

- Jerarquía visual clara: estado, guía, Wi-Fi, servidor, acciones y logs.
- Feedback de progreso, chip de estado, guía contextual y botón de desconexión.
- Los logs ahora muestran el evento más reciente y están acotados.

**Riesgos**

- **i18n incompleta:** `home_screen.dart`, `network_diagnostics_view.dart`, `server_selection_panel.dart`, `connection_logs_widget.dart` y los textos de `HomeController` están en español hardcodeado. Cambiar locale a inglés no traduce la interfaz.
- El tema claro/oscuro no cambia realmente el fondo: `HomeScreen` fija un gradiente oscuro; `ThemeMode.system` no produce una experiencia clara coherente.
- No hay `Semantics` explícitos para estado, logs o progreso; la accesibilidad depende de widgets básicos.
- Logs con emojis y detección de error por `❌`; debería usarse un modelo de entrada con nivel.
- El botón de reset abre un diálogo con textos hardcodeados y sin confirmación destructiva adicional.

**Veredicto:** la UI es funcional y legible, pero no cumple aún una promesa bilingüe ni una accesibilidad sistemática.

### 3.5 Build, CI y release

**Fortalezas**

- Flutter CI ejecuta analyze y tests; el run `40996941437` terminó correctamente.
- Hay workflows separados para Windows y Apple.
- Scripts de empaquetado e instaladores documentados.

**Riesgos**

- `windows_build.yml` solo corre por tag `v*` o manual; un push a `master` no valida el build Windows.
- Apple CI `40996941485` quedó encolado; una ejecución previa se canceló tras 24h. La validación macOS/iOS no es confiable todavía.
- `pubspec.yaml` declaraba Flutter >=3.19 aunque el código usa APIs de 3.27. **Corregido** a >=3.27.
- Android/iOS/macOS no tienen build/validación local en este entorno.

**Veredicto:** CI Flutter verde, pero la matriz de release no está cerrada.

### 3.6 Pruebas y observabilidad

- Suite actual: **47 pruebas, todas OK**.
- Cobertura de líneas: **55.4%** (`753/1358`).
- Módulos con cobertura baja o nula:
  - `default_network_diagnostics.dart`: 0%
  - `default_rdp_launcher.dart`: 0%
  - `default_wifi_manager.dart`: 0%
  - `default_route_manager.dart`: 34.7%
  - `home_controller.dart`: 45.4%
- El `widget_test.dart` solo verifica que la shell renderiza; no cubre interacción, i18n ni estados de error.
- No hay pruebas de los plugins nativos ni de integración real con `mstsc`, WLAN o `route`.

**Veredicto:** base de pruebas útil para core y rollback, insuficiente para declarar release multiplataforma.

## 4. Matriz de hallazgos

| ID | Severidad | Hallazgo | Evidencia | Estado |
|---|---|---|---|---|
| SEC-01 | Media | Sanitizador Dart de interfaz más permisivo que validadores nativos | `input_sanitizer.dart`, `MainActivity.kt`, `MainFlutterWindow.swift` | **Corregido** (modo estricto Android) |
| SEC-02 | Baja | `.rdp` temporal incluye usuario/dominio | `windows/runner/rdp_launcher_plugin.cc` | Mitigado: sin contraseña, borrado posterior |
| SEC-03 | Baja | Windows conserva clave en perfil WLAN | `wifi_manager_plugin.cc` | **Documentado** en README |
| SEC-04 | Alta | macOS sin helper privilegiado para rutas | `macos/Runner/MainFlutterWindow.swift` | **Fuera de alcance**: split tunnel macOS declarado no soportado en README |
| SEC-05 | Media | iOS sin NetworkExtension | `ios/Runner/AppDelegate.swift` | **Fuera de alcance**: split tunnel iOS declarado no soportado en README |
| SEC-06 | Media | Force-unwrap de `engine` en iOS | `ios/Runner/AppDelegate.swift` | **Corregido** |
| AND-01 | Media | Android sin canal `wifi_manager`; escaneo/conexión Wi-Fi no implementados | `MainActivity.kt`, `default_wifi_manager.dart` | **Documentado**: requiere red preexistente |
| FUN-01 | Alta | `splitTunnelActive` falso positivo al iniciar paso | `home_controller.dart` | **Corregido** |
| FUN-02 | Media | Servidor autoseleccionado no persistido | `home_controller.dart` | **Corregido** |
| FUN-03 | Media | Contraseña Wi-Fi retenida tras conexión only-Wi-Fi | `home_controller.dart` | **Corregido** |
| FUN-04 | Baja | Puerto inválido silencioso | `home_controller.dart` | **Corregido** (fallback + log) |
| FUN-05 | Media | Ping a 8.8.8.8 no representa conectividad hospitalaria | `home_controller.dart` | **Corregido** (host RDP/gateway) |
| FUN-06 | Media | Diagnóstico oculta causa de fallo | `default_network_diagnostics.dart` | **Corregido** (`lastProbeError`) |
| FUN-07 | Media | Clasificación de errores por texto/emoji | `home_controller.dart` | **Corregido** (`MedLinkErrorType`) |
| ARQ-01 | Media | `HomeController` monolítico (1294 líneas) | `home_controller.dart` | **Mitigado parcialmente**: presets/logs y guías de error extraídos; el controlador sigue grande |
| ARQ-02 | Media | `mobile_rdp` desconectado y con proxy en memoria | `lib/mobile_rdp/` | **Decidido**: PoC aislado, fuera del release |
| UI-01 | Alta | i18n incompleta pese a ARB es/en | `home_screen.dart`, widgets, controlador, workflow | **Corregido**: UI, guías y logs del workflow localizados es/en |
| UI-02 | Media | Tema claro/oscuro no reflejado en fondo | `home_screen.dart`, `app_theme.dart` | **Corregido** |
| UI-03 | Media | Sin semántica/accesibilidad sistemática | widgets UI | **Corregido** (estado, pasos y logs) |
| UI-04 | Baja | Logs usan emoji para nivel de error | `home_controller.dart`, `connection_logs_widget.dart` | **Corregido** (logs estructurados) |
| BLD-01 | Alta | Piso Flutter/SDK incompatible con APIs usadas | `pubspec.yaml` | **Corregido** |
| BLD-02 | Media | Windows build no corre en push/PR | `.github/workflows/build-desktop.yml` | **Corregido** |
| BLD-03 | Media | Apple CI encolado / validación inestable | run `40996941485` | **Mitigado**: workflow manual |
| BLD-04 | Media | Android heredaba `targetSdk` de Flutter | `android/app/build.gradle.kts` | **Corregido**: `compileSdk`/`targetSdk` 36 |
| TEST-01 | Media | Cobertura 64,8%, módulos nativos/UI sin pruebas | `coverage/lcov.info` | **Parcial**: 75 pruebas, UI y diagnóstico cubiertos |
| TEST-02 | Media | Sin pruebas de integración reales de red/RDP | `integration_test/` | **Parcial**: smoke Linux real y harness opt-in; falta hardware/CI externa |

## 5. Plan de acción

### P0 — Cerrado en este commit

1. Alinear versiones de Flutter/SDK.
2. Corregir transición de estado del túnel.
3. Persistir la selección automática de servidor.
4. Acotar logs y mostrar el evento reciente.
5. Limpiar contraseña Wi-Fi tras intento only-Wi-Fi.
6. Hacer visible el fallback de puerto inválido.
7. Ignorar artefactos de cobertura.

### P1 — Antes de un release Windows formal

1. Completar i18n de toda la UI y de los textos de guía.
2. Sustituir clasificación por strings por códigos de error tipados.
3. Cambiar el diagnóstico de Internet a un objetivo configurable (gateway/host RDP/DNS hospitalario).
4. Añadir pruebas de `connect()` exitoso, errores de Wi-Fi, RDP no disponible y persistencia.
5. Añadir pruebas de widgets para estados, i18n y acciones.
6. Ejecutar build Windows en push/PR y probar en un equipo con `mstsc` y red real.

### P2 — Trabajo de plataforma

1. Implementar helper privilegiado macOS o retirar macOS de la matriz soportada.
2. Implementar NetworkExtension iOS o declarar iOS no soportado para split tunnel.
3. Decidir el destino de `mobile_rdp` (eliminar el PoC o conectarlo con FreeRDP).
4. Añadir semántica/accesibilidad y revisar contraste en tema claro.
5. Estabilizar CI Apple y presupuestar tiempo de ejecución.

## 6. Verificación ejecutada

```text
flutter analyze lib test  → No issues found
flutter test              → 47 tests passed
coverage                  → 55.4% líneas (753/1358)
CI Flutter                → run 40996941437 success
CI Apple                  → run 40996941485 queued al último chequeo
```

## 7. Conclusión

MedLink Connect tiene un núcleo Windows coherente, con controles de seguridad razonables y un flujo de conexión bien pensado. La deuda principal no está en el camino feliz de Windows, sino en la **integridad de producto**: i18n incompleta, UI no accesible de forma sistemática, cobertura insuficiente en UI/nativo y soporte macOS/iOS incompleto.

Con las correcciones P0 aplicadas, el proyecto queda en mejor posición para una validación Windows controlada. Un release multiplataforma requeriría cerrar P1 y resolver explícitamente el alcance de macOS/iOS/mobile_rdp.

## 8. Actualización 2026-10-30

- **UI-01 cerrado:** toda la UI visible, las guías, los registros del controlador, las etiquetas de perfiles RDP y los presets de servidor usan `AppLocalizations` (es/en).
- `HomeController` recibe `AppLocalizations` por inyección; la suite usa `AppLocalizationsEs` y se añadió una prueba de widget que valida el cambio a inglés.
- Verificación ejecutada tras el cambio:

```text
flutter analyze lib test  → No issues found
flutter test              → 48 tests passed
```


## 9. Actualización 2026-10-30 (P1)

- **FUN-07 cerrado:** `MedLinkErrorType` clasifica permisos, Wi-Fi, rutas, RDP,
  red, validación y errores desconocidos. La UI ya no inspecciona texto ni
  emojis para elegir la guía.
- **FUN-05 cerrado:** el diagnóstico básico usa el host RDP configurado o el
  gateway; si no hay objetivo, lo informa y omite el ping.
- **FUN-06 cerrado:** `NetworkDiagnostics.lastProbeError` conserva la causa
  (timeout, error de plataforma o plugin ausente) y se muestra en el registro.
- **UI-02/03/04 cerrados:** fondo claro/oscuro coherente con el tema, semántica
  para estado/pasos/logs y entradas de log estructuradas sin emojis.
- **SEC-01 corregido:** el sanitizador aplica el charset estricto de Android
  (`[A-Za-z0-9_.:-]`) sin romper alias de Windows.
- **SEC-06 corregido:** los canales iOS usan `vc.binaryMessenger` sin forzar el
  unwrap del motor.
- **SEC-03 documentado:** README explica que Windows conserva la clave en el
  perfil WLAN del SO.
- **ARQ-02 decidido:** `mobile_rdp`/FreeRDP queda como PoC aislado, no importado
  y fuera de los instaladores de escritorio.
- **BLD-02/BLD-03:** build de escritorio en push/PR y workflow Apple solo manual.
- **TEST-01 parcial:** se añadieron pruebas de `DefaultNetworkDiagnostics`,
  objetivos de diagnóstico, errores tipados y logs estructurados.

```text
flutter analyze lib test  → No issues found
flutter test              → 60 tests passed
```

## 10. Actualización 2026-10-30 (verificación Android)

- **Build Android reparado:** `android/app/build.gradle.kts` no aplicaba los
  plugins `com.android.application`, `kotlin-android` ni
  `dev.flutter.flutter-gradle-plugin`, por lo que Flutter abortaba con
  «unsupported Gradle project». Se añadió el bloque `plugins`.
- **NDK alineado:** se fijó `ndkVersion = "27.0.12077973"`, la versión que
  requieren `flutter_secure_storage`, `path_provider_android` y
  `shared_preferences_android`.
- Entorno de validación: Flutter 3.27.4, Temurin JDK 17, Android SDK 35,
  build-tools 35.0.0 y NDK 27.0.12077973.
- Sin dispositivo físico ni `/dev/kvm`, por lo que no se ejecutó la app en un
  terminal Android. Queda pendiente la prueba runtime de Wi-Fi, root/rutas y
  lanzamiento del cliente RDP externo.

```text
flutter build apk --debug        → OK
flutter build apk --release      → OK (22.2 MB)
flutter build appbundle --release → OK (23.1 MB)
flutter analyze lib test         → No issues found
flutter test                     → 60 tests passed
```

Artefactos: `dist/Android/MedLinkConnect_0.1.0.apk` y
`dist/Android/MedLinkConnect_0.1.0.aab`, firmados con la clave de depuración.

## 11. Actualización 2026-10-30 (endurecimiento Android/Linux y verificación)

### Cerrado o mitigado

- **Rutas Android:** `runShell` lee la salida en un hilo separado y aplica
  timeout de 20 s sin bloquearse; se eliminó el host de ping por defecto;
  `flushDns`/`clearCaches` exigen root y comprueban el código de salida.
- **Rollback Android:** se registran las rutas añadidas y se eliminan con
  coincidencia exacta de `via`/`dev`; el seguimiento está sincronizado para
  evitar carreras entre conexiones.
- **Verificación de rutas:** el canal Android valida argumentos y parsea tokens
  exactos, evitando falsos positivos por subcadenas. Dart valida subredes,
  gateway e interfaz antes de invocar el canal.
- **Privilegios Linux:** `run_privileged` solo recurre a `pkexec` cuando `sudo`
  falla por falta de TTY/credenciales, no ante errores normales del comando.
  `flushDns` devuelve `error_comando` si ninguna estrategia funciona.
- **Controlador:** reset bloqueado durante operaciones y abortado si quedan
  rutas previas; el SSID vacío se guarda explícitamente; las redes Wi-Fi se
  deduplican/ordenan; el diagnóstico usa gateway/interfaz recién sincronizados
  y rechaza valores inválidos antes de tocar el nativo.
- **Rollback:** un fallo al deshabilitar el túnel ya no marca el túnel como
  inactivo, evitando que la UI oculte rutas todavía presentes.
- **Lifecycle:** las notificaciones del controlador se omiten tras `dispose`.
- **Apple CI:** runners migrados a `macos-15`; `pod install` deja de enmascarar
  errores con `|| true`.

### Verificación ejecutada

```text
flutter analyze lib test          → No issues found
flutter test --coverage           → 67 tests passed
cobertura de líneas               → 63,3 % (1072/1694)
flutter build apk --debug         → OK
flutter build apk --release       → OK (22.2 MB)
flutter build appbundle --release → OK (23.1 MB)
flutter build linux --release     → OK
```

### Hallazgos abiertos en ese momento (ver sección 12 para el estado actual)

| ID | Severidad | Estado |
|---|---|---|
| ARQ-01 | Media | `HomeController` sigue siendo un monolito; no se refactorizó en esta sesión. |
| SEC-04 | Alta | macOS sin helper privilegiado; split tunnel no operativo. |
| SEC-05 | Media | iOS requiere NetworkExtension; limitación de plataforma. |
| TEST-02 | Media | Sin pruebas de integración reales de Wi-Fi, root, rutas y RDP. |
| UI-01 | Baja | `connection_workflow_service.dart` aún emite mensajes de log en español hardcodeado; el resto de UI/guías está localizado. |
| BLD-04 | Media | Flutter 3.27 fija `targetSdk` heredado; revisar el requisito de Google Play 2026 antes de publicar en Android. |
| NAT-01 | Baja | macOS conserva ramas de rutas inalcanzables por el bloqueo de métodos privilegiados. |

No se pudo validar Windows, macOS ni iOS localmente en este entorno; la
verificación de esas plataformas queda sujeta a CI y a equipos reales.

## 12. Actualización 2026-10-30 (bloques finales)

### Bloque 1 — i18n del workflow y Android 36

- **UI-01 cerrado:** `ConnectionWorkflowService` recibe `AppLocalizations` y
  todos sus logs/errores visibles usan claves es/en.
- **BLD-04 cerrado:** `compileSdk` y `targetSdk` fijados en 36. El APK release
  declara `minSdk 21`, `targetSdk 36` y `compileSdk 36`.
- SDK 36 y build-tools 36 instalados y usados en la compilación local.

### Bloque 2 — Refactor y alcance macOS/iOS

- **ARQ-01 mitigado parcialmente:** `ServerPreset`, `ConnectionLogEntry` y
  `ConnectionLogStore` se movieron a `home_models.dart`; la clasificación y las
  guías de error se movieron a `error_guidance.dart`. `HomeController` conserva
  1294 líneas y sigue siendo el principal punto de complejidad.
- **SEC-04/SEC-05 fuera de alcance:** README declara explícitamente que el split
  tunnel macOS/iOS no está soportado en este release. El código muerto de rutas
  macOS permanece y no se anuncia como funcionalidad.

### Bloque 3 — Integración nativa

- Añadido `integration_test/app_integration_test.dart` con arranque real de la
  app y llamadas reales a los canales Linux de diagnóstico y rutas.
- Añadido `integration_test/live_network_test.dart` opt-in para RDP, Wi-Fi y
  rutas privilegiadas mediante `--dart-define`.
- **TEST-02 parcial:** el smoke Linux pasa; la validación Wi-Fi/root/RDP real y
  el CI Windows/macOS/iOS siguen pendientes de hardware, red hospitalaria y
  publicación de los cambios.
- **AND-01 (nuevo, Media):** Android no registra el canal
  `com.medlinkconnect/wifi_manager`; escaneo/conexión Wi-Fi no están
  implementados. La app solo puede partir de una red ya conectada en Android.
  README corregido para no prometer lo contrario.

### Verificación ejecutada

```text
flutter analyze lib test integration_test       → No issues found
flutter test --coverage                         → 75 tests passed
cobertura de líneas                             → 64,8 % (1132/1747)
flutter test integration_test/app_integration_test.dart -d linux
                                                 → 3 tests passed
flutter build linux --release                   → OK
flutter build apk --release                     → OK (22.2 MB)
flutter build appbundle --release               → OK (23.0 MB)
```

### Pendiente externo

1. Ejecutar `live_network_test.dart` en un Android/Windows con Wi-Fi
   hospitalaria, root/Administrador y servidor RDP alcanzable.
2. Publicar los cambios y validar CI Windows/macOS/iOS, incluida la ejecución
   del smoke de integración en cada plataforma.
3. Decidir si se implementa el canal Wi-Fi Android (AND-01) o se mantiene el
   alcance documentado de red preexistente.

### Para retomar la próxima sesión

```bash
export PATH=/home/daniel/flutter/bin:/home/daniel/.local/jdk-17/bin:$PATH
flutter pub get
flutter analyze lib test integration_test
flutter test --coverage
xvfb-run -a flutter test integration_test/app_integration_test.dart -d linux
```

Estado del árbol: cambios sin commit. No se publicó nada en GitHub. Antes de
continuar, revisar `git status`; el siguiente paso requiere autorización para
commit/push o acceso a hardware/red hospitalaria para las pruebas live.
