# Acta de Liberacion de Version Publicada

## 1. Datos generales

- Producto: `MedLink Connect`
- Version base de referencia: `0.1.0+1`
- Documento: `Acta de liberacion / release notes tecnicas`
- Plataforma de liberacion validada: `Windows`

## 2. Objetivo de la liberacion

Formalizar la salida de una version funcional orientada a facilitar la
conexion a infraestructura hospitalaria por escritorio remoto, con foco en:

- estabilidad,
- soporte guiado al usuario,
- diagnostico,
- seguridad local del cliente,
- y mejor experiencia operativa.

## 3. Alcance de la liberacion

### Incluido

- UI de conexion guiada
- escaneo y conexion Wi-Fi en Windows
- deteccion de SSID, gateway e interfaz
- configuracion de tunel dividido
- verificacion de rutas
- diagnostico ICMP y TCP
- seleccion de perfil RDP
- seleccion manual o automatica del servidor
- apertura de cliente RDP
- proteccion de seguridad local en el lanzador RDP

### No incluido como alcance cerrado de publicacion multiplataforma

- binarios finales compilados para Android
- binarios finales compilados para iPhone
- binarios finales compilados para macOS
- binarios finales compilados para Linux

Estas plataformas quedaron adaptadas en codigo, pero no cerradas como release
operativa equivalente en el mismo host de trabajo.

## 4. Cambios principales de la version

## 4.1 Flujo de red

Se consolidaron mejoras para:

- mantener la configuracion Wi-Fi objetivo,
- esperar confirmacion real de conexion,
- detectar gateway e interfaz activos,
- y evitar continuar si la base de red no esta lista.

## 4.2 Tunel dividido

Se reforzo la gestion del tunel dividido con:

- alta de rutas por subred,
- verificacion posterior,
- rollback de cambios en caso de fallo,
- y mejor lectura del estado de red.

## 4.3 Diagnostico

Se añadieron o reforzaron:

- `ping` al servidor,
- prueba TCP al puerto de RDP,
- reintentos cortos,
- solucionador de problemas,
- y guidance visual para usuarios no tecnicos.

## 4.4 RDP

Se mejoro el lanzador para:

- pantalla completa,
- confirmacion de arranque del cliente,
- seleccion adaptativa del perfil,
- portapapeles habilitado,
- y mayor consistencia en el uso de `mstsc.exe`.

## 4.5 Servidores preconfigurados

Se añadieron cinco servidores institucionales:

1. `serv_pediatrico.huv.gov.co`
2. `serv_ginecologico.huv.gov.co`
3. `serv_moviles.huv.gov.co`
4. `serv_const_ext.huv.gov.co`
5. `serv_urgencias.huv.gov.co`

Ademas:

- se permite seleccion manual,
- o diagnostico y seleccion automatica del mas estable.

## 4.6 Seguridad local del cliente

Se ajustaron aspectos sensibles del lanzamiento RDP:

- copiar y pegar habilitado por portapapeles,
- discos locales ya no redirigidos por defecto,
- y limpieza del archivo `.rdp` temporal despues del lanzamiento.

## 5. Arquitectura liberada

### Capa compartida Flutter

- `lib/main.dart`
- `lib/features/ui/home_screen.dart`
- `lib/features/settings/settings_service.dart`

Responsable de:

- UI,
- orquestacion del flujo,
- persistencia local no sensible,
- seleccion de servidor,
- y logica de apoyo al usuario.

### Interfaces de capacidades

- `lib/core/network_diagnostics.dart`
- `lib/core/route_manager.dart`
- `lib/core/rdp_launcher.dart`
- `lib/core/wifi_manager.dart`

### Implementaciones Flutter por channel

- `lib/features/health_check/default_network_diagnostics.dart`
- `lib/features/split_tunnel/default_route_manager.dart`
- `lib/features/rdp_launcher/default_rdp_launcher.dart`
- `lib/features/wifi/default_wifi_manager.dart`

### Plugins nativos principales

#### Windows

- `windows/runner/wifi_manager_plugin.cc`
- `windows/runner/network_diagnostics_plugin.cc`
- `windows/runner/route_manager_plugin.cc`
- `windows/runner/rdp_launcher_plugin.cc`

#### Android

- `android/app/src/main/kotlin/com/medlinkconnect/medlink_connect/MainActivity.kt`

#### iPhone

- `ios/Runner/AppDelegate.swift`

#### macOS

- `macos/Runner/MainFlutterWindow.swift`

#### Linux

- `linux/runner/network_diagnostics_plugin.cc`
- `linux/runner/route_manager_plugin.cc`
- `linux/runner/rdp_launcher_plugin.cc`

## 6. Validaciones realizadas

En el cierre de la version se ejecutaron validaciones repetidas:

```powershell
dart analyze
flutter test
flutter build windows --release
```

Resultado:

- `dart analyze` -> satisfactorio
- `flutter test` -> satisfactorio
- `flutter build windows --release` -> satisfactorio en el ciclo de cierre

## 7. Artefacto de salida

Ejecutable Windows release:

`build\windows\x64\runner\Release\medlink_connect.exe`

## 8. Estado por plataforma

### Windows

- release funcional
- validado como plataforma principal

### Android

- codigo adaptado
- build pendiente por falta de Android SDK en este entorno

### iPhone

- codigo adaptado
- build pendiente en host Apple

### macOS

- codigo adaptado
- build pendiente en host Apple

### Linux

- codigo adaptado
- build pendiente en host Linux

## 9. Riesgos residuales

Persisten riesgos operativos normales del dominio:

- necesidad de privilegios elevados para ciertas rutas,
- politicas del servidor remoto que pueden bloquear funciones como portapapeles,
- disponibilidad real del servidor RDP,
- y necesidad de infraestructura nativa para generar builds finales fuera de
  Windows.

No se identifican en esta version:

- contraseñas Wi-Fi persistidas,
- contraseñas RDP persistidas,
- ni comparticion local de discos por defecto en la sesion remota.

## 10. Criterio de aprobacion de liberacion

La version puede considerarse apta para:

- `publicacion controlada en Windows`,
- `piloto operativo`,
- y `continuacion del roadmap multiplataforma`.

No debe declararse aun como:

- liberacion plenamente equivalente en Android, iPhone, macOS y Linux.

## 11. Recomendaciones posteriores a la liberacion

1. ejecutar piloto real en Windows,
2. validar los cinco servidores en campo,
3. confirmar copiar/pegar contra servidores reales,
4. cerrar toolchains nativos para Android y Apple,
5. y completar una ronda de build/QA por plataforma.

## 12. Veredicto final del acta

La version publicada de MedLink Connect queda aceptable como liberacion
operativa de `Windows`, con mejoras claras en:

- estabilidad,
- experiencia de usuario,
- seguridad local del cliente,
- control del flujo tecnico,
- y preparacion de la base multiplataforma.

La liberacion se considera:

- `Aprobada para Windows en despliegue controlado`
- `Preparada para evolucion multiplataforma en la siguiente fase`
