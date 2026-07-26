# Configuración Inicial - HAPPYCONNECTION v2.0

## 🚀 Inicio Rápido

### 1. Configurar datos del hospital

Edita `config/hospital_config.json` con los datos de tu hospital:

```json
{
  "hospital": {
    "name": "Tu Hospital",
    "code": "HOSP-001"
  },
  "network": {
    "his_interface": "eth0",        // Interfaz red HIS
    "wifi_interface": "wlan0",      // Interfaz WiFi
    "his_gateway": "10.0.0.1",     // Gateway HIS
    "his_subnet": "10.0.0.0/24",   // Subnet HIS
    "wifi_gateway": "192.168.1.1"   // Gateway WiFi
  },
  "rdp": {
    "server": "rdp.hospital.local",  // Servidor RDP
    "port": 3389,
    "domain": "HOSPITAL",
    "resolution": "1920x1080"
  }
}
```

### 2. Compilar aplicación

**Windows:**
```bash
scripts\build_windows.bat
```

**macOS:**
```bash
bash scripts/build_macos.sh
```

**Linux:**
```bash
bash scripts/build_linux.sh
```

### 3. Ejecutar

**Windows:**
```bash
dist\HAPPYCONNECTION\happyconnection.exe
```

**macOS:**
```bash
open dist/HAPPYCONNECTION/happyconnection.app
```

**Linux:**
```bash
./dist/HAPPYCONNECTION/happyconnection
```

## 🔐 Configuración de Seguridad

### Certificados SSL/TLS

1. Obtener certificados del hospital
2. Copiar en:
   - Windows: `%APPDATA%\HAPPYCONNECTION\certs\`
   - macOS/Linux: `~/.config/happyconnection/certs/`

### Credenciales

Las credenciales RDP se introducen en la interfaz gráfica.
Nunca se guardan en texto plano.

## 📊 Monitoreo

- **Latencia HIS**: Mostrada en tiempo real
- **Estado WiFi**: Indicador de conectividad
- **Log de actividad**: Auditable y encriptado
- **Auto-reconexión**: Cada 5 segundos

## 🔧 Solución de problemas

### Conexión rechazada

```bash
# Verificar interfaz de red
ifconfig (macOS/Linux)
ipconfig (Windows)

# Verificar conectividad
ping 10.0.0.1
```

### Purga IP manual

**Linux/macOS:**
```bash
sudo nmcli connection down <interface>
sudo dhclient -r <interface>
sudo dhclient <interface>
sudo nmcli connection up <interface>
```

**Windows:**
```cmd
ipconfig /release
ipconfig /renew
```

### Logs detallados

Cambia en `config/hospital_config.json`:
```json
"log_level": "DEBUG"
```

## 📱 Versión Móvil (iOS/Android)

### Generar APK (Android)

```bash
cd flutter
flutter build apk --release
```

Luego distribuir: `build/app/outputs/flutter-apk/app-release.apk`

### Generar IPA (iOS)

```bash
cd flutter
flutter build ios --release
```

Luego cargar en App Store Connect.

## ✅ Checklist de Implementación

- [ ] Configurar datos del hospital
- [ ] Instalar certificados SSL/TLS
- [ ] Compilar aplicación
- [ ] Probar conexión HIS
- [ ] Verificar reconexión automática
- [ ] Revisar logs auditable
- [ ] Distribuir a médicos
- [ ] Capacitación de usuarios

## 📞 Soporte

Para ayuda: support@happyconnection.medical
