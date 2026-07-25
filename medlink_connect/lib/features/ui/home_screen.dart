import 'package:flutter/material.dart';
import 'package:medlink_connect/core/network_diagnostics.dart';
import 'package:medlink_connect/core/route_manager.dart';
import 'package:medlink_connect/core/rdp_launcher.dart';

/// The main home screen for MedLink Connect.
///
/// Provides one-tap access to network diagnostics and RDP connection launch.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.networkDiagnostics,
    required this.routeManager,
    required this.rdpLauncher,
  });

  final NetworkDiagnostics networkDiagnostics;
  final RouteManager routeManager;
  final RdpLauncher rdpLauncher;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _busy = false;
  String _status = 'Ready';

  Future<void> _runDiagnostics() async {
    setState(() {
      _busy = true;
      _status = 'Running diagnostics…';
    });

    try {
      final dnsResult = await widget.networkDiagnostics.flushDns();
      final cacheResult = await widget.networkDiagnostics.clearNetworkCaches();
      final pingResult = await widget.networkDiagnostics.ping('8.8.8.8');

      final buffer = StringBuffer();
      buffer.writeln(dnsResult);
      buffer.writeln(cacheResult);
      if (pingResult != null) {
        buffer.writeln('Ping: ${pingResult}ms');
      } else {
        buffer.writeln('Ping: unreachable');
      }

      setState(() => _status = buffer.toString().trim());
    } catch (e) {
      setState(() => _status = 'Diagnostics failed: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MedLink Connect')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Icon(Icons.monitor_heart_outlined,
                        size: 48, color: Colors.blue),
                    const SizedBox(height: 12),
                    Text(_status, textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _runDiagnostics,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: const Text('Connect'),
            ),
          ],
        ),
      ),
    );
  }
}
