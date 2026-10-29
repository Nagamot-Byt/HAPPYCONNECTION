========================================================================
             MEDLINK CONNECT — PAQUETE DE INSTALACIÓN LINUX
========================================================================

INSTALACIÓN EN 1 CLIC:

1. Haz doble clic en "MedLinkConnect_Linux_<arch>.run".
   (También puedes ejecutar ./MedLinkConnect_Linux_<arch>.run en una terminal.)
2. El instalador copia la aplicación a ~/.local/share/medlink_connect
   y crea accesos directos en el Menú de Aplicaciones y el Escritorio.
3. Inicia "MedLink Connect" desde tu Menú o Escritorio.

ALTERNATIVA PORTABLE:

- Extrae MedLinkConnect_Linux_<arch>.tar.gz y ejecuta
  ./instalar_medlink_connect.sh.

ALTERNATIVA DEBIAN/UBUNTU:

- sudo apt install ./medlink-connect_<version>_<arch>.deb

NOTAS:

- Las rutas del túnel dividido requieren sudo/polkit; la app lo solicita
  cuando hace falta.
- El Wi-Fi automático no está implementado en Linux; conecta la red desde
  los ajustes del sistema y pulsa "Detectar red actual".

========================================================================
