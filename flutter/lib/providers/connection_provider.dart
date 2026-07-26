import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import '../models/connection_status.dart';

class ConnectionProvider with ChangeNotifier {
  late WebSocketChannel _channel;
  bool _isConnected = false;
  List<String> _logs = [];
  ConnectionStatus? _status;

  bool get isConnected => _isConnected;
  List<String> get logs => _logs;
  ConnectionStatus? get connectionStatus => _status;

  Future<void> initialize() async {
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
      _addLog('✅ Conectado al servidor');
      notifyListeners();
    } catch (e) {
      _addLog('❌ Error de conexión: $e');
    }
  }

  void _handleMessage(dynamic message) {
    _addLog('📨 Mensaje recibido: $message');
    notifyListeners();
  }

  void connect() {
    _addLog('🔗 Conectando...');
    _sendCommand('connect');
  }

  void disconnect() {
    _addLog('🔌 Desconectando...');
    _sendCommand('disconnect');
  }

  void reconnect() {
    _addLog('🔄 Reconectando...');
    _sendCommand('reconnect');
  }

  void purgeIP() {
    _addLog('🌊 Purgando IP...');
    _sendCommand('purge_ip');
  }

  void toggleNetwork(String network) {
    _addLog('🔀 Alternando red: $network');
    _sendCommand('toggle_network:$network');
  }

  void _sendCommand(String command) {
    if (_isConnected) {
      _channel.sink.add('{"command":"$command"}';
    }
  }

  void _addLog(String message) {
    _logs.add('${DateTime.now().toIso8601String()} - $message');
    if (_logs.length > 50) {
      _logs.removeAt(0);
    }
  }

  @override
  void dispose() {
    _channel.sink.close(status.goingAway);
    super.dispose();
  }
}
