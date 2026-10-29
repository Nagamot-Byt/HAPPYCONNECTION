# Protocolo de reinicio - MedLink Connect

## Estado al cerrar hoy

- Flujo Wi-Fi simplificado listo.
- Verificacion extra agregada: la app no continua a tunel/RDP si no confirma la SSID conectada.
- Build Windows debug validado correctamente.

## Abrir el proyecto

1. Abrir Trae en:
   `D:\HappyConnection\HAPPYCONNECTION-feat-scaffold-project\medlink_connect`
2. Revisar que no haya archivos con cambios accidentales.

## Arranque recomendado

1. Abrir terminal en la raiz del proyecto.
2. Ejecutar:

```powershell
& "D:\flutter\bin\cache\dart-sdk\bin\dart.exe" analyze
& "D:\flutter\bin\cache\dart-sdk\bin\dart.exe" "D:\flutter\packages\flutter_tools\bin\flutter_tools.dart" run -d windows
```

## Prueba en hospital

1. Pulsar `Actualizar redes`.
2. Elegir la SSID del hospital o `Otra red...`.
3. Escribir la clave y pulsar `Conectar Wi-Fi`.
4. Confirmar que aparezca la SSID activa.
5. Abrir `Opciones avanzadas` y comprobar `Gateway` e `Interfaz`.
6. Pulsar `Conectar y abrir RDP`.

## Si algo falla

1. Repetir el arranque con salida detallada:

```powershell
& "D:\flutter\bin\cache\dart-sdk\bin\dart.exe" "D:\flutter\packages\flutter_tools\bin\flutter_tools.dart" run -d windows -v
```

2. Comparar:
   - el registro visual dentro de la app
   - la salida del terminal
3. Si Wi-Fi conecta pero no llena `Gateway` o `Interfaz`, completar esos campos manualmente y reintentar.

## Archivos clave

- `lib/features/ui/home_screen.dart`
- `lib/core/settings_storage.dart`
- `windows/runner/wifi_manager_plugin.cc`
- `README.md`
