import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:medlink_connect/features/ui/home_controller.dart';
import 'package:medlink_connect/features/ui/widgets/glass_container.dart';

class ServerSelectionPanel extends StatelessWidget {
  const ServerSelectionPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HomeController>();
    final presets = controller.serverPresets;

    return GlassContainer(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '2. Escritorio remoto',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: controller.selectedServerPresetId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Servidor preconfigurado',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(
                  value: 'manual',
                  child: Text('Manual'),
                ),
                for (final preset in presets)
                  DropdownMenuItem(
                    value: preset.id,
                    child: Text(
                      preset.isConfigured
                          ? '${preset.label} - ${preset.host}:${preset.port}'
                          : '${preset.label} - pendiente por configurar',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: controller.busy
                  ? null
                  : (value) {
                      if (value == null) return;
                      if (value == 'manual') {
                        controller.selectedServerPresetId = 'manual';
                        return;
                      }
                      final preset = controller.presetById(value);
                      if (preset == null) return;
                      if (!preset.isConfigured) {
                        controller.preferMostStableServer = false;
                        controller.selectedServerPresetId = value;
                        controller.setGuidance(
                          'Servidor pendiente de configuración',
                          bullets: [
                            'Ese cupo ya quedó reservado.',
                            'En cuanto me compartas los 5 servidores, lo dejo operativo.',
                          ],
                          isError: true,
                        );
                        return;
                      }
                      // Elegir un servidor concreto desactiva la selección
                      // automática para respetar la elección del usuario.
                      controller.preferMostStableServer = false;
                      controller.applyServerPreset(preset);
                    },
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              value: controller.preferMostStableServer,
              contentPadding: EdgeInsets.zero,
              title:
                  const Text('Elegir automáticamente el servidor más estable'),
              subtitle: Text(
                presets.isEmpty
                    ? 'La estructura para servidores ya está lista; falta cargar los datos reales.'
                    : 'La app medirá respuesta TCP y usará el mejor servidor disponible.',
              ),
              onChanged: controller.busy
                  ? null
                  : (value) {
                      controller.preferMostStableServer = value;
                    },
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: controller.busy || !controller.loaded
                    ? null
                    : () => controller.diagnoseBestServerPreset(),
                icon: const Icon(Icons.hub_outlined),
                label: const Text('Diagnosticar mejor servidor'),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: TextField(
                      controller: controller.rdpHostCtrl,
                      enabled: !controller.busy,
                      decoration: const InputDecoration(
                        labelText: 'Host / IP RDP',
                        hintText: 'serv_pediatrico.huv.gov.co',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: TextField(
                      controller: controller.rdpPortCtrl,
                      enabled: !controller.busy,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Puerto',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: TextField(
                      controller: controller.rdpUserCtrl,
                      enabled: !controller.busy,
                      decoration: const InputDecoration(
                        labelText: 'Usuario (opcional)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: TextField(
                      controller: controller.rdpDomainCtrl,
                      enabled: !controller.busy,
                      decoration: const InputDecoration(
                        labelText: 'Dominio (opcional)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            DropdownButtonFormField<String>(
              value: controller.rdpProfile,
              decoration: const InputDecoration(
                labelText: 'Perfil RDP',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(
                  value: 'adaptive',
                  child: Text('Adaptativo'),
                ),
                DropdownMenuItem(
                  value: 'stable',
                  child: Text('Máxima estabilidad'),
                ),
                DropdownMenuItem(
                  value: 'speed',
                  child: Text('Máxima velocidad'),
                ),
              ],
              onChanged: controller.busy
                  ? null
                  : (value) {
                      if (value != null) controller.rdpProfile = value;
                    },
            ),
            const SizedBox(height: 12),
            Text(
              'Adaptativo elige el perfil según la latencia al servidor. '
              'Máxima estabilidad reduce funciones visuales y reintenta más. '
              'Máxima velocidad recorta redirecciones para abrir antes.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
