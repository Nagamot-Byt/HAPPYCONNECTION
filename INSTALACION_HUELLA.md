# HAPPYCONNECTION v2.0 - Guía de Compilación e Instalación

## 🏥 Hospital Configurado: HUV (Hospital Universitario del Valle)

**Ubicación:** Cali, Colombia  
**Código:** HUV-001

---

## 📋 Servidores Disponibles

### 1. **Servidor Pediátrico** 👶
- **Dirección:** serv_pediatrico.huv.gov.co
- **Departamento:** Pediatría
- **Descripción:** Acceso a Historia Clínica Pediátrica

### 2. **Servidor Ginecológico** 👩‍⚕️
- **Dirección:** serv_ginecologico.huv.gov.co
- **Departamento:** Ginecología
- **Descripción:** Acceso a Historia Clínica Ginecológica

### 3. **Servidor Móviles** 📱
- **Dirección:** serv_moviles.huv.gov.co
- **Departamento:** Movilidad
- **Descripción:** Acceso remoto desde dispositivos móviles

### 4. **Servidor Urgencias** 🚑 (PRIORITARIO)
- **Dirección:** serv_urgencias.huv.gov.co
- **Departamento:** Urgencias
- **Descripción:** Acceso prioritario a Urgencias y Emergencias

### 5. **Servidor Consulta Externa** 🏥
- **Dirección:** serv_const_ext.huv.gov.co
- **Departamento:** Consulta Externa
- **Descripción:** Acceso a Historia Clínica Consulta Externa

---

## 🛠️ Compilación Rápida (Todas las Plataformas)

### Windows (Un Clic)
```bash
scripts\install_windows_oneclick.bat
```

### macOS/Linux (Un Clic)
```bash
bash scripts/install_oneclick.sh
```

### Compilación Manual (Todas las Plataformas)

#### Windows
```bash
bash scripts/build_all_platforms.sh
```

#### Linux/macOS
```bash
bash scripts/build_all_platforms.sh
```

---

## 📦 Distribuciones Generadas

### Windows
```
✅ dist/windows/happyconnection.exe
✅ dist/happyconnection-backend-windows.exe
```
**Tamaño:** ~200MB  
**Requisitos:** Windows 7+

### macOS (Universal)
```
✅ dist/macos/happyconnection.app
✅ dist/happyconnection-backend-macos-intel
✅ dist/happyconnection-backend-macos-arm
```
**Tamaño:** ~150MB  
**Requisitos:** macOS 10.14+

### Linux
```
✅ dist/linux/happyconnection
✅ dist/happyconnection-backend-linux
```
**Tamaño:** ~120MB  
**Requisitos:** glibc 2.28+

### Android
```
✅ dist/android/happyconnection.apk
```
**Tamaño:** ~80MB  
**Requisitos:** Android 5.0+

### iOS
```
✅ build/ios/ipa/happyconnection.ipa (mediante Xcode)
```
**Tamaño:** ~90MB  
**Requisitos:** iOS 11.0+

---

## 🚀 Instalación de Un Clic

### Windows
1. Descargar `install_windows_oneclick.bat`
2. Hacer doble clic
3. ¡Listo! Aparecerá acceso directo en el escritorio

### macOS
1. Ejecutar: `bash scripts/install_oneclick.sh`
2. Se instalará en `/Applications/HAPPYCONNECTION.app`
3. ¡Listo! Abrirlo desde Launchpad o Finder

### Linux
1. Ejecutar: `bash scripts/install_oneclick.sh`
2. Se instalará en `~/.local/opt/happyconnection`
3. ¡Listo! Ejecutar con comando `happyconnection`

### Android
1. Transferir `dist/android/happyconnection.apk` al dispositivo
2. Instalar desde archivo APK
3. ¡Listo! Abrirlo desde el menú de aplicaciones

### iOS
1. Usar TestFlight o distribución empresarial
2. Instalar en dispositivos Apple
3. ¡Listo! Abrirlo desde pantalla de inicio

---

## 🔧 Configuración del Hospital

Todos los datos están en `config/hospital_config.json`:

```json
{
  "hospital": {
    "name": "Hospital Universitario del Valle - HUV",
    "code": "HUV-001",
    "region": "Cali, Colombia"
  },
  "servers": [
    {
      "name": "Servidor Pediátrico",
      "address": "serv_pediatrico.huv.gov.co",
      "port": 3389
    },
    ...
  ]
}
```

---

## ⚡ Características de Instalación

✅ **Un Clic:** No requiere configuración manual  
✅ **Integración:** Se integra perfectamente con el SO  
✅ **Acceso Directo:** Acceso fácil desde menú/escritorio  
✅ **Actualización:** Auto-actualizable  
✅ **Múltiples Plataformas:** Windows, macOS, Linux, iOS, Android  
✅ **Bajo Consumo:** ~40-100MB según plataforma  
✅ **Sin Dependencias Externas:** Todo incluido  

---

## 🏢 Configuración Hospital Personalizada

Para agregar más servidores o cambiar configuración:

1. Editar `config/hospital_config.json`
2. Agregar nuevo servidor en array `servers`
3. Recompilar: `bash scripts/build_all_platforms.sh`
4. Distribuir nueva versión

---

## 🐛 Solución de Problemas

### Windows - No se ejecuta
```bash
# Ejecutar como Administrador
Right-click > Run as Administrator
```

### macOS - "No se puede abrir"
```bash
# Permitir en Seguridad
open /Applications/HAPPYCONNECTION.app
```

### Linux - Permiso denegado
```bash
chmod +x ~/.local/opt/happyconnection/happyconnection
```

### Android - APK no se instala
```
Habilitar: Configuración > Seguridad > Fuentes desconocidas
```

---

## 📞 Soporte

Para ayuda técnica:  
📧 support@happyconnection.huv.gov.co  
📱 (57) 2 xxx-xxxx

---

*Última actualización: 2026-07-26*  
*Versión: 2.0 - HUV Edition*
