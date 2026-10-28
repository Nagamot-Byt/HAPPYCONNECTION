MEDLINK CONNECT - Paquete .DEB para Linux

Instalación:
sudo dpkg -i medlink-connect_1.0.0_amd64.deb
sudo apt-get install -f 2>/dev/null || true

Desinstalación:
sudo apt remove medlink-connect

Notas:
- Requiere permisos de administrador (sudo) para modificar rutas estáticas (túnel dividido)
- Compatible con Ubuntu/Debian/Linux Mint (amd64)
- Se instala en /usr/share/medlink-connect con lanzador medlink-connect
- Aparece en menú de aplicaciones "MedLink Connect"
