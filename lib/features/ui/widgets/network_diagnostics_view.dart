import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:medlink_connect/features/ui/home_controller.dart';
import 'package:medlink_connect/features/ui/widgets/glass_container.dart';

class NetworkDiagnosticsView extends StatefulWidget {
  const NetworkDiagnosticsView({super.key});

  @override
  State<NetworkDiagnosticsView> createState() => _NetworkDiagnosticsViewState();
}

class _NetworkDiagnosticsViewState extends State<NetworkDiagnosticsView> {
  bool _showAdvanced = false;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HomeController>();

    return Column(
      children: [
        GlassContainer(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '1. Conexión Wi-Fi',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  controller.wifiManager == null
                      ? 'En esta plataforma la conexión Wi-Fi debe hacerse desde los ajustes del sistema. La app seguirá ayudando con diagnóstico y apertura del cliente RDP.'
                      : 'Selecciona la red, escribe la contraseña y la app intentará completar automáticamente la configuración de red necesaria.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                if (controller.wifiManager != null) ...[
                  _buildWifiSelector(context, controller),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: TextField(
                      controller: controller.wifiPasswordCtrl,
                      enabled: !controller.busy,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Contraseña Wi-Fi',
                        hintText: 'No se guarda automáticamente',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ] else
                  Text(
                    'Consejo: conéctate primero a la red necesaria desde los ajustes del sistema y luego vuelve aquí para revisar estabilidad y abrir RDP.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    OutlinedButton.icon(
                      onPressed: controller.busy ||
                              !controller.loaded ||
                              controller.wifiManager == null
                          ? null
                          : () => controller.refreshWifiNetworks(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Actualizar redes'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: controller.busy ||
                              !controller.loaded ||
                              controller.wifiManager == null
                          ? null
                          : () => controller.connectWifiOnly(),
                      icon: const Icon(Icons.wifi),
                      label: const Text('Conectar Wi-Fi'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        GlassContainer(
          child: ExpansionTile(
            initiallyExpanded: _showAdvanced,
            onExpansionChanged: (value) =>
                setState(() => _showAdvanced = value),
            title: const Text('Opciones avanzadas'),
            subtitle: const Text(
                'Solo si quieres revisar o ajustar la configuración técnica'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Estos valores se pueden completar automáticamente después de conectarte al Wi-Fi.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: controller.busy ||
                          !controller.loaded ||
                          controller.wifiManager == null
                      ? null
                      : () => controller.syncCurrentWifiInfo(silent: false),
                  icon: const Icon(Icons.my_location_outlined),
                  label: const Text('Detectar red actual'),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: TextField(
                        controller: controller.gatewayCtrl,
                        enabled: !controller.busy,
                        decoration: const InputDecoration(
                          labelText: 'Gateway',
                          hintText: 'ej: 192.168.1.1',
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
                        controller: controller.ifaceCtrl,
                        enabled: !controller.busy,
                        decoration: const InputDecoration(
                          labelText: 'Interfaz',
                          hintText: 'ej: Wi-Fi, Ethernet',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: TextField(
                  controller: controller.subnetsCtrl,
                  enabled: !controller.busy,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Subredes del hospital (una por línea)',
                    hintText: '10.0.0.0/8',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWifiSelector(BuildContext context, HomeController controller) {
    final options = <String>[
      ...controller.wifiNetworks.where((e) => e.isNotEmpty),
    ];

    if (controller.selectedWifiSsid != null &&
        controller.selectedWifiSsid != controller.manualWifiOption &&
        !controller.wifiNetworks.contains(controller.selectedWifiSsid)) {
      options.insert(0, controller.selectedWifiSsid!);
    }

    final dropdownItems = <DropdownMenuItem<String>>[
      for (final ssid in options)
        DropdownMenuItem<String>(
          value: ssid,
          child: Text(ssid),
        ),
      DropdownMenuItem<String>(
        value: controller.manualWifiOption,
        child: const Text('Otra red…'),
      ),
    ];

    final value = (() {
      final selected = controller.selectedWifiSsid;
      if (selected == null || selected.isEmpty) return null;
      if (selected == controller.manualWifiOption) {
        return controller.manualWifiOption;
      }
      return options.contains(selected)
          ? selected
          : controller.manualWifiOption;
    })();

    return Column(
      children: [
        DropdownButtonFormField<String>(
          value: value,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Red Wi-Fi',
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: controller.wifiNetworksLoading
                ? const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
          items: dropdownItems,
          onChanged: controller.busy
              ? null
              : (val) {
                  controller.selectedWifiSsid = val;
                  if (val != null && val != controller.manualWifiOption) {
                    controller.manualWifiCtrl.text = val;
                  }
                },
        ),
        const SizedBox(height: 12),
        if (controller.selectedWifiSsid == controller.manualWifiOption ||
            controller.wifiNetworks.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: TextField(
              controller: controller.manualWifiCtrl,
              enabled: !controller.busy,
              decoration: const InputDecoration(
                labelText: 'Nombre de la red Wi-Fi',
                hintText: 'Ej: Hospital-Staff',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
      ],
    );
  }
}
