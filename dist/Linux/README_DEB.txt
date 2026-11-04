MEDLINK CONNECT - Paquete .DEB para Linux

Instalación (usa el nombre real del archivo generado):
ls medlink-connect_*_amd64.deb
sudo apt install ./medlink-connect_*_amd64.deb

Alternativa con dpkg:
sudo dpkg -i medlink-connect_*_amd64.deb
sudo apt-get install -f

Desinstalación:
sudo apt remove medlink-connect

Notas:
- Requiere permisos de administrador (sudo) para modificar rutas estáticas (túnel dividido)
- El Wi-Fi usa NetworkManager (nmcli); debe estar activo y autorizado para tu usuario
- Compatible con Ubuntu/Debian/Linux Mint (amd64)
- Se instala en /usr/lib/medlink-connect y el lanzador es /usr/bin/medlink-connect
- Aparece en el menú de aplicaciones como "MedLink Connect"
- Si el comando dice "No existe el archivo o el directorio", el nombre o la
  versión no coinciden. Ejecuta `ls medlink-connect_*_amd64.deb` para ver el
  archivo disponible en esta carpeta.
