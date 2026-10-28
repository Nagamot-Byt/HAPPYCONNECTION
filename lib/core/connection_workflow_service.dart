import 'dart:async';
import 'package:injectable/injectable.dart';
import 'package:medlink_connect/core/route_manager.dart';
import 'package:medlink_connect/core/wifi_manager.dart';
import 'package:medlink_connect/core/network_diagnostics.dart';
import 'package:medlink_connect/core/rdp_launcher.dart';
import 'package:medlink_connect/core/exceptions.dart';
import 'package:medlink_connect/core/input_sanitizer.dart';
import 'package:medlink_connect/features/ui/home_controller.dart'
    show ConnectionStep;

class WorkflowState {
  final ConnectionStep step;
  final String logMessage;
  final bool isError;
  final bool isFinished;

  const WorkflowState({
    required this.step,
    required this.logMessage,
    this.isError = false,
    this.isFinished = false,
  });
}

@lazySingleton
class ConnectionWorkflowService {
  final RouteManager routeManager;
  final WifiManager? wifiManager;
  final NetworkDiagnostics networkDiagnostics;
  final RdpLauncher rdpLauncher;

  ConnectionWorkflowService(
      this.routeManager, this.networkDiagnostics, this.rdpLauncher,
      {this.wifiManager});

  Stream<WorkflowState> connect({
    required List<String> subnets,
    required String host,
    required String user,
    required String domain,
    required String selectedWifi,
    required String gateway,
    required String iface,
    required int resolvedPort,
    required bool preferMostStableServer,
    String rdpProfile = 'adaptive',
    String? wifiPassword,
  }) async* {
    var splitTunnelEnabledThisAttempt = false;

    yield const WorkflowState(
      step: ConnectionStep.diagnostics,
      logMessage: '🚀 Iniciando flujo completo de conexión…',
    );

    try {
      // Validate inputs using InputSanitizer
      final sanitizedHost =
          InputSanitizer.sanitizeHostname(host, fieldName: 'Servidor RDP');
      final sanitizedSubnets =
          InputSanitizer.sanitizeSubnets(subnets, fieldName: 'Subredes');
      final sanitizedGateway =
          InputSanitizer.sanitizeIpv4(gateway, fieldName: 'Puerta de enlace');
      final sanitizedIface =
          InputSanitizer.sanitizeInterfaceName(iface, fieldName: 'Interfaz');

      String currentGateway = sanitizedGateway;
      String currentIface = sanitizedIface;

      if (wifiManager != null && selectedWifi.isNotEmpty) {
        final sanitizedSsid = InputSanitizer.sanitizeSsid(selectedWifi);
        yield const WorkflowState(
          step: ConnectionStep.diagnostics,
          logMessage: 'Paso 0/4 — Conectando a Wi-Fi',
        );
        await wifiManager!.connect(
          ssid: sanitizedSsid,
          password: wifiPassword != null && wifiPassword.isNotEmpty
              ? wifiPassword
              : null,
        );
        // Esperar a que Windows confirme conexión y obtenga gateway/interfaz
        for (var i = 0; i < 12; i++) {
          await Future<void>.delayed(Duration(seconds: i == 0 ? 2 : 1));
          try {
            final info = await routeManager.getPrimaryDefaultRouteInfo();
            final g = (info['gateway'] ?? '').trim();
            final inf = (info['interfaceName'] ?? '').trim();
            if (g.isNotEmpty) currentGateway = g;
            if (inf.isNotEmpty) currentIface = inf;
            if (currentGateway.isNotEmpty && currentIface.isNotEmpty) {
              yield WorkflowState(
                step: ConnectionStep.diagnostics,
                logMessage:
                    'Wi-Fi conectado. Gateway $currentGateway, Interfaz $currentIface.',
              );
              break;
            }
          } catch (_) {}
        }
        if (currentGateway.isEmpty || currentIface.isEmpty) {
          yield const WorkflowState(
            step: ConnectionStep.diagnostics,
            logMessage:
                'No se detectaron gateway/interfaz automáticamente. Se usarán los valores configurados.',
            isError: true,
          );
        }
      } else {
        currentGateway = sanitizedGateway;
        currentIface = sanitizedIface;
      }

      yield const WorkflowState(
        step: ConnectionStep.splitTunnel,
        logMessage:
            'Paso 1/4 — Preparando la conexión\nSe omiten resets agresivos de red para evitar demoras y cortes innecesarios.',
      );

      if (currentGateway.isEmpty || currentIface.isEmpty) {
        throw RouteConfigurationException(
          'Faltan gateway o interfaz para habilitar el túnel dividido. Usa "Detectar red actual" o completa los campos en Opciones avanzadas.',
        );
      }

      yield WorkflowState(
        step: ConnectionStep.splitTunnel,
        logMessage:
            'Paso 2/4 — Habilitando túnel dividido para ${sanitizedSubnets.length} subred(es)',
      );

      final splitMsg = await routeManager.enableSplitTunnel(
        hospitalSubnets: sanitizedSubnets,
        gateway: currentGateway,
        interfaceName: currentIface,
      );

      yield WorkflowState(
          step: ConnectionStep.splitTunnel, logMessage: splitMsg);
      splitTunnelEnabledThisAttempt = true;

      await Future<void>.delayed(const Duration(milliseconds: 600));
      final missingRoutes = await routeManager.verifyRoutes(
        hospitalSubnets: sanitizedSubnets,
        gateway: currentGateway,
        interfaceName: currentIface,
      );

      if (missingRoutes.isNotEmpty) {
        throw RouteConfigurationException(
          'No se verificaron todas las rutas del hospital. Faltan: ${missingRoutes.join(', ')}.',
        );
      }

      yield const WorkflowState(
          step: ConnectionStep.preLaunch,
          logMessage: 'Rutas del hospital verificadas correctamente.');

      yield const WorkflowState(
        step: ConnectionStep.preLaunch,
        logMessage: 'Paso 3/4 — Verificando alcance al destino y cliente RDP',
      );

      final hostPing = await networkDiagnostics.ping(sanitizedHost);
      if (hostPing != null) {
        yield WorkflowState(
            step: ConnectionStep.preLaunch,
            logMessage: 'Host RDP $sanitizedHost responde en ${hostPing}ms.');
      } else {
        yield WorkflowState(
          step: ConnectionStep.preLaunch,
          logMessage:
              'El host RDP no respondió a ICMP. Si el servidor bloquea ping, se intentará abrir RDP de todos modos.',
          isError: true,
        );
      }

      final tcpConnectTime =
          await networkDiagnostics.checkTcpPort(sanitizedHost, resolvedPort);
      if (tcpConnectTime == null) {
        throw RdpTimeoutException(
          'No se pudo abrir el puerto TCP $resolvedPort en $sanitizedHost. Revisa rutas, firewall o disponibilidad del servidor RDP.',
        );
      }
      yield WorkflowState(
          step: ConnectionStep.preLaunch,
          logMessage:
              'Puerto TCP $resolvedPort accesible en ${tcpConnectTime}ms.');

      yield const WorkflowState(
          step: ConnectionStep.launchRdp,
          logMessage: 'Paso 4/4 — Lanzando conexión RDP');

      final available = await rdpLauncher.isRdpClientAvailable();
      if (!available) {
        throw RdpLaunchException(
          'No hay un cliente RDP instalado. Instala o habilita Microsoft Remote Desktop Connection.',
        );
      }

      final launchResult = await rdpLauncher.launchRdp(
        host: sanitizedHost,
        port: resolvedPort,
        username: user.isEmpty ? null : user,
        domain: domain.isEmpty ? null : domain,
        profile: rdpProfile,
        measuredLatencyMs: tcpConnectTime,
      );

      yield WorkflowState(
          step: ConnectionStep.done,
          logMessage: launchResult,
          isFinished: true);
    } catch (e) {
      if (splitTunnelEnabledThisAttempt) {
        yield const WorkflowState(
          step: ConnectionStep.error,
          logMessage: 'Re-deshabilitando túnel dividido debido a error...',
        );
        try {
          await routeManager.disableSplitTunnel();
          yield const WorkflowState(
            step: ConnectionStep.error,
            logMessage: 'Túnel dividido deshabilitado correctamente.',
          );
        } catch (disableError) {
          yield WorkflowState(
            step: ConnectionStep.error,
            logMessage: 'No se pudo deshabilitar el túnel: $disableError',
            isError: true,
          );
        }
      }

      String errorMsg = e.toString();
      if (e is MedLinkException) {
        errorMsg = e.message;
      }
      yield WorkflowState(
          step: ConnectionStep.error,
          logMessage: '❌ Error: $errorMsg',
          isError: true,
          isFinished: true);
    }
  }
}
