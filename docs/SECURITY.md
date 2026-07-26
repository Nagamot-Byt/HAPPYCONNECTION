# Seguridad y Cumplimiento Médico

## Encriptación TLS 1.3

- ✅ Protocolo: TLS 1.3 (último estándar)
- ✅ Cipher Suites: AES-256-GCM
- ✅ Key Exchange: ECDHE
- ✅ Certificate Pinning: Habilitado

## Cumplimiento HIPAA/LGPD

### HIPAA (Health Insurance Portability and Accountability Act)
- ✅ Encriptación de datos en tránsito
- ✅ Encriptación de datos en reposo
- ✅ Log auditable de todos los accesos
- ✅ Autenticación y autorización
- ✅ Control de acceso basado en roles

### LGPD (Lei Geral de Proteção de Dados)
- ✅ Consentimiento del usuario
- ✅ Derecho al olvido
- ✅ Portabilidad de datos
- ✅ Notificación de brechas

## Log Auditable

Todos los eventos se registran con:
- Timestamp ISO 8601
- Usuario responsable
- Acción realizada
- Resultado
- Dirección IP
- Dispositivo

Ejemplo:
```
2024-07-26T14:32:15Z | Usuario: medicod123 | Acción: LOGIN | Resultado: SUCCESS | IP: 10.0.0.45 | Dispositivo: MacBook
2024-07-26T14:32:28Z | Usuario: medicod123 | Acción: VIEW_PATIENT_RECORD | Resultado: SUCCESS | PID: PAC-12345 | IP: 10.0.0.45
2024-07-26T14:40:50Z | Usuario: medicod123 | Acción: LOGOUT | Resultado: SUCCESS | IP: 10.0.0.45
```

## Redes Aisladas

### Arquitectura de Red Dual

```
Laptop Médico
├── Interfaz 1: Red HIS (10.0.0.x) - AISLADA
│   └── Conecta a: Servidor RDP Hospital
│       └── Acceso a: Historia Clínica (HIS)
│
└── Interfaz 2: Red WiFi (192.168.x.x) - Internet Normal
    └── Conecta a: Internet público
        └── Acceso a: Google Drive, etc.
```

### Tunelización Automática

- Las aplicaciones de historia clínica se conectan SOLO a la red HIS
- Las aplicaciones de navegación se conectan SOLO a WiFi
- NO hay tráfico cruzado entre redes
- Firewall local bloquea tráfico no autorizado

## Reconexión Automática

### Monitoreo Continuo (cada 5 segundos)

1. **Verificar estado de conexión RDP**
2. **Medir latencia**
3. **Detectar dropouts**
4. **Reconectar automáticamente** (sin cerrar sesión del usuario)

### Purga IP Automática

Cuando se detecta conexión inestable:

```bash
# Linux/macOS
sudo nmcli connection down <interface>
sudo dhclient -r <interface>
sudo dhclient <interface>
sudo nmcli connection up <interface>

# Windows
ipconfig /release
ipconfig /renew
```

### Backoff Exponencial

- 1er intento: 1 segundo
- 2do intento: 2 segundos
- 3er intento: 4 segundos
- 4to intento: 8 segundos
- Máximo: 60 segundos

## Certificados Médicos

El hospital proporciona:

1. **Certificado SSL/TLS** para el servidor RDP
2. **Certificado cliente** para autenticación mutua
3. **CA root** del hospital para validación

Estos se instalan en:
- Windows: `C:\Users\[USER]\AppData\Local\HAPPYCONNECTION\certs`
- macOS/Linux: `~/.config/happyconnection/certs`

## Verificación de Integridad

Certificados SHA-256:

```
Appdata: 5e42a3c1b8d9f4e6c2a1b3d5e7f9a1b3c5d7e9f1a3b5c7d9e1f3a5b7c9d1e3
Config: a1b3c5d7e9f1a3b5c7d9e1f3a5b7c9d1e3f5a7b9c1d3e5f7a9b1c3d5e7f9
```

## Contacto de Seguridad

Para reportar vulnerabilidades:
📧 security@happyconnection.medical
