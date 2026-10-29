import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:medlink_connect/features/ui/home_controller.dart';
import 'package:medlink_connect/features/ui/widgets/connection_logs_widget.dart';
import 'package:medlink_connect/features/ui/widgets/network_diagnostics_view.dart';
import 'package:medlink_connect/features/ui/widgets/server_selection_panel.dart';
import 'package:medlink_connect/features/ui/widgets/guidance_panel.dart';
import 'package:medlink_connect/features/ui/widgets/connection_action_buttons.dart';
import 'package:medlink_connect/features/ui/widgets/connection_step_indicator.dart';
import 'package:medlink_connect/core/network_diagnostics.dart';
import 'package:medlink_connect/core/route_manager.dart';
import 'package:medlink_connect/core/rdp_launcher.dart';
import 'package:medlink_connect/core/wifi_manager.dart';
import 'package:medlink_connect/core/settings_storage.dart';
import 'package:medlink_connect/core/connection_workflow_service.dart';
import 'package:medlink_connect/core/injection.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<HomeController>(
      create: (_) => HomeController(
        settings: getIt.isRegistered<SettingsStorage>()
            ? getIt<SettingsStorage>()
            : null,
        wifiManager:
            getIt.isRegistered<WifiManager>() ? getIt<WifiManager>() : null,
        routeManager: getIt<RouteManager>(),
        networkDiagnostics: getIt<NetworkDiagnostics>(),
        rdpLauncher: getIt<RdpLauncher>(),
        workflowService: getIt<ConnectionWorkflowService>(),
      )..init(),
      child: const _HomeScreenContent(),
    );
  }
}

class _HomeScreenContent extends StatelessWidget {
  const _HomeScreenContent();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HomeController>();

    final stepColor = switch (controller.step) {
      ConnectionStep.done => Colors.green,
      ConnectionStep.error => Colors.red,
      _ => Theme.of(context).colorScheme.primary,
    };

    final stepText = switch (controller.step) {
      ConnectionStep.idle => controller.splitTunnelActive
          ? 'Túnel dividido activo'
          : (controller.loaded ? 'Listo para conectar' : 'Cargando…'),
      ConnectionStep.diagnostics => 'Preparando conexión…',
      ConnectionStep.splitTunnel => 'Configurando rutas…',
      ConnectionStep.preLaunch => 'Verificando destino y cliente RDP…',
      ConnectionStep.launchRdp => 'Lanzando RDP…',
      ConnectionStep.done => 'Conectado',
      ConnectionStep.error => 'Error',
    };

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0F172A),
            Color(0xFF003049),
            Color(0xFF1565C0),
            Color(0xFF00897B),
          ],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(AppLocalizations.of(context)!.appTitle),
          actions: [
            IconButton(
              tooltip: 'Restablecer ajustes',
              onPressed: controller.busy || controller.settings == null
                  ? null
                  : () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: const Text('Restablecer ajustes'),
                          content: const Text(
                              'Se borrarán las subredes, credenciales RDP y '
                              'preferencias guardadas. ¿Continuar?'),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(false),
                              child: const Text('Cancelar'),
                            ),
                            FilledButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(true),
                              child: const Text('Restablecer'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await controller.resetSettings();
                      }
                    },
              icon: const Icon(Icons.restore_outlined),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Chip(
                  key: ValueKey('${controller.splitTunnelActive}_$stepText'),
                  avatar: Icon(
                    controller.splitTunnelActive
                        ? Icons.vpn_lock
                        : Icons.wifi_protected_setup,
                    size: 18,
                  ),
                  label: Text(stepText),
                  side: BorderSide(color: stepColor),
                ),
              ),
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              transitionBuilder:
                                  (Widget child, Animation<double> animation) {
                                return ScaleTransition(
                                    scale: animation, child: child);
                              },
                              child: Icon(
                                controller.step == ConnectionStep.done
                                    ? Icons.check_circle
                                    : controller.step == ConnectionStep.error
                                        ? Icons.error
                                        : Icons.circle_outlined,
                                key: ValueKey(controller.step),
                                size: 36,
                                color: stepColor,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 300),
                                    child: Text(
                                      stepText,
                                      key: ValueKey(stepText),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: stepColor,
                                          ),
                                    ),
                                  ),
                                  if (controller.currentWifiSsid.isNotEmpty)
                                    Text(
                                      'Wi-Fi actual: ${controller.currentWifiSsid}',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ConnectionStepIndicator(controller: controller),
                      ],
                    ),
                  ),
                ),
                GuidancePanel(controller: controller),
                const SizedBox(height: 16),
                const NetworkDiagnosticsView(),
                const SizedBox(height: 16),
                const ServerSelectionPanel(),
                const SizedBox(height: 16),
                ConnectionActionButtons(controller: controller),
                const SizedBox(height: 16),
                const ConnectionLogsWidget(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
