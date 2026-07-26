import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'dart:convert';
import '../models/connection_status.dart';
import '../models/server.dart';

class ConnectionProvider with ChangeNotifier {
  late WebSocketChannel _channel;
  bool _isConnected = false;
  List<String> _logs = [];
  ConnectionStatus? _status;
  Server? _selectedServer;
  List<Server> _availableServers = [];

  bool get isConnected => _isConnected;
  List<String> get logs => _logs;
  ConnectionStatus? get connectionStatus => _status;
  Server? get selectedServer => _selectedServer;
  List<Server> get availableServers => _availableServers;

  Future<void> initialize() async {
    try {
      // Cargar servidores desde configuración
      _availableServers = [
        Server(
          name: 'Servidor Pediátrico',
          code: 'SERV_PEDIATRICO',
          address: 'serv_pediatrico.huv.gov.co',
          port: 3389,
          department: 'Pediatría',
          description: 'Acceso a Historia Clínica Pediátrica',
          enabled: true,
          icon: '👶',
        ),
        Server(
          name: 'Servidor Ginecológico',
          code: 'SERV_GINECOLOGICO',
          address: 'serv_ginecologico.huv.gov.co',
          port: 3389,
          department: 'Ginecología',
          description: 'Acceso a Historia Clínica Ginecológica',
          enabled: true,
          icon: '👩‍⚕️',
        ),
        Server(
          name: 'Servidor Móviles',
          code: 'SERV_MOVILES',
          address: 'serv_moviles.huv.gov.co',
          port: 3389,
          department: 'Movilidad',
          description: 'Acceso remoto desde dispositivos móviles',
          enabled: true,
          icon: '📱',
        ),
        Server(
          name: 'Servidor Urgencias',
          code: 'SERV_URGENCIAS',
          address: 'serv_urgencias.huv.gov.co',
          port: 3389,
          department: 'Urgencias',
          description: 'Acceso prioritario a Urgencias y Emergencias',
          enabled: true,
          icon: '🚑',
          priority: true,
        ),
        Server(
          name: 'Servidor Consulta Externa',
          code: 'SERV_CONST_EXT',
          address: 'serv_const_ext.huv.gov.co',
          port: 3389,
          department: 'Consulta Externa',
          description: 'Acceso a Historia Clínica Consulta Externa',
          enabled: true,
          icon: '🏥',
        ),
      ];

      _connectWebSocket();
      _addLog('✅ Servidores del hospital cargados');
      notifyListeners();
    } catch (e) {
      _addLog('❌ Error al inicializar: $e');
    }
  }

  void _connectWebSocket() {
    try {
      _channel = WebSocketChannel.connect(
        Uri.parse('ws://localhost:8443/ws'),
      );

      _channel.stream.listen(
        (message) {
          _handleMessage(message);
        },
        onDone: () {
          _isConnected = false;
          _addLog('❌ Desconectado del servidor');
          notifyListeners();
        },
        onError: (error) {
          _addLog('⚠️ Error: $error');
        },
      );

      _isConnected = true;
      _addLog('✅ Conectado al backend');
      notifyListeners();
    } catch (e) {
      _addLog('❌ Error de conexión: $e');
    }
  }

  void _handleMessage(dynamic message) {
    _addLog('📨 Mensaje: $message');
    notifyListeners();
  }

  void connectToServer(Server server) {
    _selectedServer = server;
    _addLog('🔗 Conectando a ${server.name}...');
    _addLog('   Dirección: ${server.address}:${server.port}');
    _addLog('   Departamento: ${server.department}');
    _sendCommand('connect_server', {
      'server_code': server.code,
      'address': server.address,
      'port': server.port,
    });
    notifyListeners();
  }

  void connect() {
    _addLog('🔗 Conectando...');
    _sendCommand('connect', {});
  }

  void disconnect() {
    _addLog('❌ Desconectando...');
    _sendCommand('disconnect', {});
    _selectedServer = null;
    notifyListeners();
  }

  void reconnect() {
    _addLog('🔄 Reconectando...');
    _sendCommand('reconnect', {});
  }

  void purgeIP() {
    _addLog('🌊 Purgando IP...');
    _sendCommand('purge_ip', {});
  }

  void toggleNetwork(String network) {
    _addLog('🔀 Alternando red: $network');
    _sendCommand('toggle_network', {'network': network});
  }

  void _sendCommand(String command, Map<String, dynamic> params) {
    if (_isConnected) {
      final message = jsonEncode({
        'command': command,
        'params': params,
        'timestamp': DateTime.now().toIso8601String(),
      });
      _channel.sink.add(message);
    }
  }

  void _addLog(String message) {
    _logs.add('${DateTime.now().toIso8601String()} - $message');
    if (_logs.length > 100) {
      _logs.removeAt(0);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _channel.sink.close(status.goingAway);
    super.dispose();
  }
}
