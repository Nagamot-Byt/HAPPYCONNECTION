import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/connection_provider.dart';
import '../models/server.dart';
import '../widgets/server_list.dart';
import '../widgets/network_status_widget.dart';
import '../widgets/connection_controls.dart';
import '../widgets/activity_log.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => context.read<ConnectionProvider>().initialize(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '🏥 HAPPYCONNECTION - HUV',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        actions: [
          Consumer<ConnectionProvider>(
            builder: (context, provider, _) {
              return Padding(
                padding: const EdgeInsets.all(16.0),
                child: Center(
                  child: Text(
                    provider.isConnected ? '● Conectado' : '● Desconectado',
                    style: TextStyle(
                      color: provider.isConnected ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Encabezado con logo del hospital
            Card(
              color: Colors.grey[900],
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Text(
                      '🏢',
                      style: TextStyle(fontSize: 40),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Hospital Universitario del Valle',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const Text(
                      'Cali, Colombia',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Estado de redes
            const NetworkStatusWidget(),
            const SizedBox(height: 16),

            // Lista de servidores disponibles
            const ServerListWidget(),
            const SizedBox(height: 16),

            // Controles
            const ConnectionControls(),
            const SizedBox(height: 16),

            // Log de actividad
            const ActivityLog(),
          ],
        ),
      ),
    );
  }
}
