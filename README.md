# HAPPYCONNECTION v2.0

**Conexión RDP Médica Segura y Estable**

Aplicación multiplataforma para conexión segura a sistemas de historia clínica (HIS) con soporte para red dual (HIS + Internet).

## Características

✅ **Red Dual Automática**: Túnel entre red HIS (localhost) y WiFi normal  
✅ **Estabilidad Garantizada**: Monitoreo continuo, auto-reconexión sin desconectar  
✅ **Purga IP Inteligente**: Recuperación automática de conexiones caídas  
✅ **Encriptación TLS 1.3**: Datos completamente protegidos  
✅ **Log Auditable**: Cumplimiento HIPAA/LGPD  
✅ **Multiplataforma**: Windows, macOS, Linux, iOS, Android  

## Estructura del Proyecto

```
HAPPYCONNECTION/
├── backend/                    # Servicio Go (backend)
│   ├── main.go
│   ├── config/
│   ├── network/
│   ├── security/
│   └── go.mod
├── flutter/                    # App Flutter (UI multiplataforma)
│   ├── lib/
│   ├── pubspec.yaml
│   └── android/, ios/, windows/, linux/
├── mobile/                     # Visualización historia clínica móvil
│   ├── lib/
│   └── pubspec.yaml
├── docs/                       # Documentación médica
├── scripts/                    # Scripts de instalación
└── config/                     # Configuración
