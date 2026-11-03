========================================================================
             MEDLINK CONNECT — PAQUETE DE INSTALACIÓN macOS
========================================================================

INSTALACIÓN EN 1 CLIC:

1. Haz doble clic en "MedLinkConnect-macOS-Installer.command".
2. El instalador copia "MedLink Connect.app" a /Applications, elimina la
   cuarentena de macOS y abre la aplicación.
3. Si macOS muestra una advertencia de seguridad, haz clic derecho sobre el
   instalador y elige "Abrir". Repite el mismo paso con la aplicación si
   vuelve a aparecer la advertencia.
4. Si el sistema indica que el archivo no se puede ejecutar porque se
   descargó por internet, abre Terminal en esta carpeta y ejecuta:
     chmod +x MedLinkConnect-macOS-Installer.command
     ./MedLinkConnect-macOS-Installer.command

VERSIÓN PORTABLE:

- Descomprime "MedLinkConnect_macOS_Portable.zip" y arrastra
  "MedLink Connect.app" a /Applications.
- Si macOS bloquea la aplicación, haz clic derecho y elige "Abrir".

COMPATIBILIDAD:

- Aplicación universal para Mac con Intel (x86_64) y Apple Silicon (arm64).
- Requiere macOS 10.14 o posterior.
- La aplicación no está notarizada por Apple. El instalador aplica una firma
  local ad-hoc, elimina la cuarentena y abre la app; si Gatekeeper la bloquea,
  usa clic derecho > "Abrir".

NOTAS:

- El túnel dividido privilegiado no está disponible en esta compilación de
  macOS; la aplicación continúa usando las rutas del sistema.
- Artefacto generado a partir del commit 4ce6ac2.

========================================================================
