import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/connection_provider.dart';
import '../models/server.dart';

class ServerListWidget extends StatelessWidget {
  const ServerListWidget({Key? key}) : super(key: key);

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
              '📋 SERVIDORES DISPONIBLES',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Consumer<ConnectionProvider>(
              builder: (context, provider, _) {
                final servers = provider.availableServers;
                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: servers.length,
                  separatorBuilder: (_, __) => Divider(
                    color: Colors.grey[700],
                    height: 12,
                  ),
                  itemBuilder: (context, index) {
                    final server = servers[index];
                    return _ServerCard(server: server);
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ServerCard extends StatelessWidget {
  final Server server;

  const _ServerCard({required this.server});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: server.priority ? Colors.orange : Colors.grey[700]!,
          width: server.priority ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Text(
            server.icon,
            style: const TextStyle(fontSize: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  server.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  server.department,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  server.address,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white54,
                    fontFamily: 'Courier',
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: server.enabled
                ? () => context.read<ConnectionProvider>().connectToServer(server)
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: server.priority ? Colors.orange : Colors.green,
              disabledBackgroundColor: Colors.grey[600],
            ),
            child: const Text(
              'Conectar',
              style: TextStyle(
                fontSize: 11,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
