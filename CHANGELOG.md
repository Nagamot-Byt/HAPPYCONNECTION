# Changelog

Todas las versiones relevantes de MedLink Connect.

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

### Cambiado

- Documentación reorganizada: auditoría en `docs/audits/` y notas de release
  consolidadas en este changelog.
- README actualizado con instalación, compilación en un clic y enlaces de
  descarga.

### Corregido

- Hallazgos de la auditoría ToT 2026-10-29, incluido UI-01 (localización).
- Flujo de conexión endurecido con validaciones y limpieza segura de rutas.

### Verificación

- `flutter analyze lib test`: sin incidencias.
- `flutter test`: 48 pruebas correctas.
- Build Linux release validado localmente.
- Build Windows e instalador generados por CI.
