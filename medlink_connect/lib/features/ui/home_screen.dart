import 'package:flutter/material.dart';
import 'package:medlink_connect/core/network_diagnostics.dart';
import 'package:medlink_connect/core/rdp_launcher.dart';
import 'package:medlink_connect/core/route_manager.dart';

/// The primary screen of MedLink Connect.
///
/// Shows network status, provides a one-tap "Connect" action that:
/// 1. Runs network diagnostics (DNS flush, cache clear, ping)
/// 2. Enables split-tunneling for the hospital subnet
/// 3. Launches Microsoft Remote Desktop via deep link
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
  bool _isBusy = false;
  String _status = 'Ready';
  int? _latencyMs;

  Future<void> _onConnect() async {
    setState(() {
      _isBusy = true;
      _status = 'Running diagnostics…';
    });

    try {
      // Step 1 – DNS flush & cache clear
      final dnsOk = await widget.networkDiagnostics.flushDns();
      final cacheOk = await widget.networkDiagnostics.clearNetworkCaches();
      if (!dnsOk || !cacheOk) {
        setState(() => _status = '⚠ DNS / cache clear failed');
        return;
      }

      // Step 2 – Ping check
      setState(() => _status = 'Pinging…');
      final latency = await widget.networkDiagnostics.ping('8.8.8.8');
      setState(() => _latencyMs = latency);
      if (latency == null) {
        setState(() => _status = '⚠ No internet — check connection');
        return;
      }

      // Step 3 – Enable split tunnel (placeholder)
      setState(() => _status = 'Enabling split tunnel…');
      await widget.routeManager.enableSplitTunnel(
        hospitalSubnets: const ['10.0.0.0/8'],
        hospitalGateway: '10.0.0.1',
        hospitalInterface: 'eth0',
      );

      // Step 4 – Launch RDP
      setState(() => _status = 'Launching RDP client…');
      final launched = await widget.rdpLauncher.launchRdp(
        address: '10.0.0.100',
        username: '',
      );

      setState(() {
        _status = launched ? '✅ Connected' : '⚠ RDP client not found';
        _isBusy = false;
      });
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
        _isBusy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('MedLink Connect'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(
                      _status.startsWith('⚠')
                          ? Icons.warning_amber_rounded
                          : _status.startsWith('✅')
                              ? Icons.check_circle_outline
                              : Icons.info_outline,
                      size: 48,
                      color: _status.startsWith('⚠')
                          ? Colors.orange
                          : _status.startsWith('✅')
                              ? Colors.green
                              : theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _status,
                      style: theme.textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    if (_latencyMs != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Latency: $_latencyMs ms',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Connect button
            FilledButton.icon(
              onPressed: _isBusy ? null : _onConnect,
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
              label: Text(_isBusy ? 'Connecting…' : 'Connect'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: theme.textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 16),
            // Info text
            Text(
              'MedLink Connect prepares your network for hospital RDP access. '
              'It flushes DNS, clears caches, enables split-tunneling, and '
              'launches the Microsoft Remote Desktop client.',
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
}
