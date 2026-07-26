package main

import (
	"crypto/tls"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"

	"github.com/gorilla/websocket"
)

var (
	upgrader = websocket.Upgrader{
		ReadBufferSize:  1024,
		WriteBufferSize: 1024,
		CheckOrigin: func(r *http.Request) bool {
			return true // Permitir conexiones locales
		},
	}

	connections = make(map[string]*websocket.Conn)
	connMutex   sync.RWMutex
)

type ConnectionStatus struct {
	Status    string    `json:"status"`
	Timestamp time.Time `json:"timestamp"`
	Latency   int64     `json:"latency_ms"`
	HISNet    bool      `json:"his_network"`
	WiFi      bool      `json:"wifi_network"`
}

type NetworkMonitor struct {
	hisInterface  string
	wifiInterface string
	monitorTicker *time.Ticker
}

func main() {
	fmt.Println("\n🏥 HAPPYCONNECTION v2.0 - Backend Service")
	fmt.Println("=" * 50)

	// Crear monitor de red
	monitor := &NetworkMonitor{
		hisInterface:  "eth0",     // Configurar según SO
		wifiInterface: "wlan0",    // Configurar según SO
	}

	// Iniciar monitoreo en background
	go monitor.startMonitoring()

	// Rutas HTTP
	http.HandleFunc("/ws", handleWebSocket)
	http.HandleFunc("/health", handleHealth)
	http.HandleFunc("/config", handleConfig)

	// Servidor HTTPS con TLS 1.3
	server := &http.Server{
		Addr: ":8443",
		TLSConfig: &tls.Config{
			MinVersion:               tls.VersionTLS13,
			CurvePreferences:        []tls.CurveID{tls.CurveP521, tls.CurveP384},
			PreferServerCipherSuites: true,
		},
	}

	fmt.Println("\n✅ Servidor iniciado en: wss://localhost:8443")
	fmt.Println("✅ WebSocket disponible en: wss://localhost:8443/ws")
	fmt.Println("\n📋 Esperando conexiones...\n")

	// Manejo de señales de cierre
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		<-sigChan
		fmt.Println("\n🛑 Cerrando servicio...")
		server.Close()
		os.Exit(0)
	}()

	// Iniciar servidor (HTTP en desarrollo, HTTPS en producción)
	err := server.ListenAndServe()
	if err != nil && err != http.ErrServerClosed {
		log.Fatal("Error al iniciar servidor:", err)
	}
}

func handleWebSocket(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Println("Error en WebSocket:", err)
		return
	}
	defer conn.Close()

	clientID := r.RemoteAddr
	connMutex.Lock()
	connections[clientID] = conn
	connMutex.Unlock()

	fmt.Printf("\n✅ Cliente conectado: %s\n", clientID)

	// Monitoreo de conexión
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			// Enviar status de conexión cada 5 segundos
			status := ConnectionStatus{
				Status:    "connected",
				Timestamp: time.Now(),
				Latency:   int64(time.Now().UnixMilli() % 50), // Simulación
				HISNet:    true,
				WiFi:      true,
			}

			conn.WriteJSON(status)

		default:
			// Leer mensajes del cliente
			var msg map[string]interface{}
			err := conn.ReadJSON(&msg)
			if err != nil {
				if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
					log.Printf("Error WebSocket: %v", err)
				}
				return
			}

			handleClientMessage(conn, msg)
		}
	}
}

func handleClientMessage(conn *websocket.Conn, msg map[string]interface{}) {
	if command, ok := msg["command"]; ok {
		fmt.Printf("📤 Comando recibido: %v\n", command)

		response := map[string]interface{}{
			"command": command,
			"status":  "executed",
			"time":    time.Now().Unix(),
		}

		conn.WriteJSON(response)
	}
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	fmt.Fprintf(w, `{"status":"healthy","timestamp":%d}`, time.Now().Unix())
}

func handleConfig(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	fmt.Fprintf(w, `{"his_gateway":"10.0.0.1","wifi_gateway":"192.168.1.1","rdp_server":"rdp.hospital.local"}`)
}

func (m *NetworkMonitor) startMonitoring() {
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()

	for range ticker.C {
		// Monitorear interfaz HIS
		hisUp := m.checkInterface(m.hisInterface)
		wifiUp := m.checkInterface(m.wifiInterface)

		if !hisUp {
			fmt.Println("⚠️  Red HIS desconectada, intentando reconectar...")
			m.reconnectInterface(m.hisInterface)
		}

		if !wifiUp {
			fmt.Println("⚠️  Red WiFi desconectada, intentando reconectar...")
			m.reconnectInterface(m.wifiInterface)
		}

		// Notificar a clientes conectados
		connMutex.RLock()
		for _, conn := range connections {
			status := ConnectionStatus{
				Status:    "monitoring",
				Timestamp: time.Now(),
				HISNet:    hisUp,
				WiFi:      wifiUp,
			}
			conn.WriteJSON(status)
		}
		connMutex.RUnlock()
	}
}

func (m *NetworkMonitor) checkInterface(iface string) bool {
	// Implementar verificación de interfaz de red
	return true // Placeholder
}

func (m *NetworkMonitor) reconnectInterface(iface string) {
	// Implementar reconexión automática
	// Ejecutar: nmcli connection down <iface> && nmcli connection up <iface>
	fmt.Printf("🔄 Reconectando interfaz: %s\n", iface)
}
