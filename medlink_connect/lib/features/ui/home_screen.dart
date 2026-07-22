import 'package:flutter/material.dart';
import 'package:medlink_connect/core/network_diagnostics.dart';
import 'package:medlink_connect/core/rdp_launcher.dart';
import 'package:medlink_connect/core/route_manager.dart';

/// Estados del pipeline de conexión.
enum _ConnectionState {
  idle,
  runningDiagnostics,
  enablingTunnel,
  launchingRdp,
  connected,
  failed,
}

/// Pantalla principal de MedLink Connect.
///
/// Muestra el estado de la red, ejecuta diagnósticos, habilita
/// split-tunneling y lanza el cliente de Escritorio Remoto de Microsoft
/// mediante deep linking.
class HomeScreen extends StatefulWidget {
  final NetworkDiagnostics networkDiagnostics;
  final RouteManager routeManager;
  final RdpLauncher rdpLauncher;

  const HomeScreen({
    super.key,
    required this.networkDiagnostics,
    required this.routeManager,
    required this.rdpLauncher,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  _ConnectionState _connectionState = _ConnectionState.idle;
  String _statusMessage = 'Listo para conectar';
  int? _latencyMs;
  String? _errorMessage;

  bool get _isBusy =>
      _connectionState == _ConnectionState.runningDiagnostics ||
      _connectionState == _ConnectionState.enablingTunnel ||
      _connectionState == _ConnectionState.launchingRdp;

  Future<void> _onConnect() async {
    // ---- Step 1: Flush DNS ----
    setState(() {
      _connectionState = _ConnectionState.runningDiagnostics;
      _statusMessage = 'Limpiando DNS…';
      _errorMessage = null;
      _latencyMs = null;
    });

    try {
      final dnsOk = await widget.networkDiagnostics.flushDns();
      if (!dnsOk) {
        setState(() {
          _connectionState = _ConnectionState.failed;
          _errorMessage = 'No se pudo limpiar la caché DNS';
          _statusMessage = 'Fallo en diagnóstico de red';
        });
        return;
      }
    } catch (e) {
      setState(() {
        _connectionState = _ConnectionState.failed;
        _errorMessage = 'Error al limpiar DNS: $e';
        _statusMessage = 'Fallo en diagnóstico de red';
      });
      return;
    }

    // ---- Step 2: Clear network caches ----
    setState(() {
      _statusMessage = 'Limpiando cachés…';
    });

    try {
      await widget.networkDiagnostics.clearNetworkCaches();
    } catch (e) {
      setState(() {
        _connectionState = _ConnectionState.failed;
        _errorMessage = 'Error al limpiar cachés: $e';
        _statusMessage = 'Fallo en diagnóstico de red';
      });
      return;
    }

    // ---- Step 3: Ping connectivity check ----
    setState(() {
      _statusMessage = 'Verificando conectividad…';
    });

    try {
      final latency = await widget.networkDiagnostics.ping('8.8.8.8');
      if (latency == null) {
        setState(() {
          _connectionState = _ConnectionState.failed;
          _errorMessage = 'Sin conexión a internet — verifique la red';
          _statusMessage = 'Fallo en verificación de conectividad';
        });
        return;
      }
      _latencyMs = latency;
    } catch (e) {
      setState(() {
        _connectionState = _ConnectionState.failed;
        _errorMessage = 'Error al verificar conectividad: $e';
        _statusMessage = 'Fallo en verificación de conectividad';
      });
      return;
    }

    // ---- Step 4: Enable split tunnel ----
    setState(() {
      _connectionState = _ConnectionState.enablingTunnel;
      _statusMessage = 'Configurando túnel dividido…';
    });

    try {
      final tunnelOk = await widget.routeManager.enableSplitTunnel(
        hospitalSubnets: const ['10.0.0.0/8'],
        hospitalGateway: '10.0.0.1',
        hospitalInterface: 'eth0',
      );
      if (!tunnelOk) {
        setState(() {
          _connectionState = _ConnectionState.failed;
          _errorMessage =
              'No se pudo configurar el túnel dividido';
          _statusMessage = 'Fallo en configuración de túnel';
        });
        return;
      }
    } catch (e) {
      setState(() {
        _connectionState = _ConnectionState.failed;
        _errorMessage = 'Error al configurar túnel dividido: $e';
        _statusMessage = 'Fallo en configuración de túnel';
      });
      return;
    }

    // ---- Step 5: Launch RDP ----
    setState(() {
      _connectionState = _ConnectionState.launchingRdp;
      _statusMessage = 'Abriendo escritorio remoto…';
    });

    try {
      final result = await widget.rdpLauncher.launchRdp(
        address: '10.0.0.100',
        username: '',
      );

      setState(() {
        _statusMessage = result.message;
        _connectionState =
            result.success
                ? _ConnectionState.connected
                : _ConnectionState.failed;
        if (!result.success) {
          _errorMessage = result.errorCode ?? result.message;
        }
      });
    } catch (e) {
      setState(() {
        _connectionState = _ConnectionState.failed;
        _errorMessage = 'Error al lanzar RDP: $e';
        _statusMessage = 'Error al abrir escritorio remoto';
      });
    }
  }

  void _onRetry() {
    setState(() {
      _connectionState = _ConnectionState.idle;
      _statusMessage = 'Listo para conectar';
      _errorMessage = null;
      _latencyMs = null;
    });
    _onConnect();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('MedLink Connect'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_ethernet),
            tooltip: 'Perfiles',
            onPressed: () {
              Navigator.of(context).pushNamed('/profiles');
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Configuración',
            onPressed: () {
              Navigator.of(context).pushNamed('/settings');
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---- Status card ----
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(
                      _statusIcon(),
                      size: 48,
                      color: _statusColor(theme),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _statusMessage,
                      style: theme.textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    if (_latencyMs != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Latencia: $_latencyMs ms',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ---- Progress indicator during connection ----
            if (_isBusy) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
              Text(
                _statusMessage,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
            ],

            // ---- Failure: error text + retry button ----
            if (_connectionState == _ConnectionState.failed) ...[
              if (_errorMessage != null) ...[
                Text(
                  _errorMessage!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.red,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
              ],
              FilledButton.icon(
                onPressed: _onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: theme.textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 8),
            ],

            // ---- Success text ----
            if (_connectionState == _ConnectionState.connected) ...[
              Text(
                'Conexión establecida exitosamente',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.green,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
            ],

            // ---- "Conectar" button ----
            if (!_isBusy &&
                _connectionState != _ConnectionState.connected) ...[
              FilledButton.icon(
                onPressed:
                    _connectionState == _ConnectionState.failed
                        ? _onRetry
                        : _onConnect,
                icon: _isBusy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.sensors),
                label: const Text('Conectar'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: theme.textTheme.titleMedium,
                ),
              ),
            ],

            const SizedBox(height: 16),

            // ---- Info text ----
            Text(
              'MedLink Connect prepara su red para acceder al '
              'escritorio remoto del hospital. Limpia DNS, borra '
              'cachés, habilita túnel dividido e inicia el cliente '
              'de Escritorio Remoto de Microsoft.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  IconData _statusIcon() {
    switch (_connectionState) {
      case _ConnectionState.idle:
        return Icons.info_outline;
      case _ConnectionState.runningDiagnostics:
        return Icons.wifi_find;
      case _ConnectionState.enablingTunnel:
        return Icons.vpn_lock;
      case _ConnectionState.launchingRdp:
        return Icons.desktop_windows;
      case _ConnectionState.connected:
        return Icons.check_circle_outline;
      case _ConnectionState.failed:
        return Icons.warning_amber_rounded;
    }
  }

  Color _statusColor(ThemeData theme) {
    switch (_connectionState) {
      case _ConnectionState.idle:
      case _ConnectionState.runningDiagnostics:
      case _ConnectionState.enablingTunnel:
      case _ConnectionState.launchingRdp:
        return theme.colorScheme.primary;
      case _ConnectionState.connected:
        return Colors.green;
      case _ConnectionState.failed:
        return Colors.orange;
    }
  }
}
