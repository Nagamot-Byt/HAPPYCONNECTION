import 'package:flutter/material.dart';

class NetworkStatusWidget extends StatelessWidget {
  const NetworkStatusWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.grey[900],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '📡 ESTADO DE REDES',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _NetworkStatusItem(
                    name: 'RED HIS',
                    icon: '🏥',
                    isConnected: true,
                    latency: 12,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _NetworkStatusItem(
                    name: 'WiFi',
                    icon: '📶',
                    isConnected: true,
                    latency: 45,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NetworkStatusItem extends StatelessWidget {
  final String name;
  final String icon;
  final bool isConnected;
  final int latency;

  const _NetworkStatusItem({
    required this.name,
    required this.icon,
    required this.isConnected,
    required this.latency,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isConnected ? Colors.green : Colors.red,
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Text(
            icon,
            style: const TextStyle(fontSize: 24),
          ),
          const SizedBox(height: 8),
          Text(
            name,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isConnected ? '✅ Conectado' : '❌ Desconectado',
            style: TextStyle(
              fontSize: 11,
              color: isConnected ? Colors.green : Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${latency}ms',
            style: const TextStyle(
              fontSize: 10,
              color: Colors.white54,
            ),
          ),
        ],
      ),
    );
  }
}
