import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

typedef SelectedRdpTarget = ({String host, int port});

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
    String rdpProfile = 'adaptive',
    String? wifiPassword,
    Future<void> Function(
      List<String> subnets,
      String gateway,
      String interfaceName,
    )? onSplitTunnelEnabled,
    Future<void> Function()? onSplitTunnelRolledBack,
    Future<void> Function()? onSplitTunnelUnavailable,
    Future<SelectedRdpTarget?> Function()? onSelectServer,
  }) async* {
    var splitTunnelEnabledThisAttempt = false;
    var splitTunnelSetupAttempted = false;

    yield const WorkflowState(
      step: ConnectionStep.diagnostics,
      logMessage: '🚀 Iniciando flujo completo de conexión…',
    );

    try {
      var effectiveHost = host;
      var effectivePort = resolvedPort;

      // Validate inputs using InputSanitizer
      final sanitizedSubnets =
          InputSanitizer.sanitizeSubnets(subnets, fieldName: 'Subredes');
      final sanitizedGateway =
          InputSanitizer.sanitizeIpv4(gateway, fieldName: 'Puerta de enlace');
      final sanitizedIface =
          InputSanitizer.sanitizeInterfaceName(iface, fieldName: 'Interfaz');
      final sanitizedUser = user.trim().isEmpty
          ? null
          : InputSanitizer.sanitizeRdpCredential(user,
              fieldName: 'Usuario RDP');
      final sanitizedDomain = domain.trim().isEmpty
          ? null
          : InputSanitizer.sanitizeRdpCredential(domain,
              fieldName: 'Dominio RDP');

      String currentGateway = sanitizedGateway;
      String currentIface = sanitizedIface;

      if (wifiManager != null && selectedWifi.isNotEmpty) {
        try {
          final sanitizedSsid = InputSanitizer.sanitizeSsid(selectedWifi);
          final targetSsid = sanitizedSsid.trim();

          var alreadyConnected = false;
          try {
            final info = await wifiManager!.getCurrentConnectionInfo();
            alreadyConnected = info.ssid.trim() == targetSsid;
            if (alreadyConnected) {
              final g = info.gateway.trim();
              final inf = info.interfaceName.trim();
              if (g.isNotEmpty) currentGateway = g;
              if (inf.isNotEmpty) currentIface = inf;
            }
          } on MissingPluginException {
            rethrow;
          } catch (_) {
            // Si la plataforma no puede consultar el Wi-Fi, se intenta conectar.
          }

          if (alreadyConnected) {
            yield WorkflowState(
              step: ConnectionStep.diagnostics,
              logMessage: 'Ya conectado a Wi-Fi "$targetSsid".',
            );
          } else {
            yield const WorkflowState(
              step: ConnectionStep.diagnostics,
              logMessage: 'Paso 0/4 — Conectando a Wi-Fi',
            );
            final connectResult = await wifiManager!.connect(
              ssid: sanitizedSsid,
              password: wifiPassword != null && wifiPassword.isNotEmpty
                  ? wifiPassword
                  : null,
            );

            var confirmed = false;
            for (var i = 0; i < 10; i++) {
              await Future<void>.delayed(const Duration(seconds: 1));
              try {
                final info = await wifiManager!.getCurrentConnectionInfo();
                if (info.ssid.trim() != targetSsid) continue;
                final g = info.gateway.trim();
                final inf = info.interfaceName.trim();
                if (g.isNotEmpty) currentGateway = g;
                if (inf.isNotEmpty) currentIface = inf;
                confirmed = true;
                yield WorkflowState(
                  step: ConnectionStep.diagnostics,
                  logMessage:
                      'Wi-Fi conectado a "$targetSsid". Gateway $currentGateway, Interfaz $currentIface.',
                );
                break;
              } catch (_) {
                // Reintentar hasta confirmar la red objetivo.
              }
            }

            if (!confirmed) {
              final detail = connectResult.trim();
              throw WifiConnectionException(
                'No se pudo confirmar la conexión Wi-Fi a "$targetSsid". '
                '${detail.isEmpty ? 'El sistema no reportó la red objetivo.' : 'Respuesta del sistema: $detail'}',
              );
            }
          }
        } on MissingPluginException {
          yield const WorkflowState(
            step: ConnectionStep.diagnostics,
            logMessage:
                'El control automático de Wi-Fi no está disponible en esta plataforma; se usará la red actual.',
            isError: true,
          );
        }

        if (currentGateway.isEmpty || currentIface.isEmpty) {
          try {
            final info = await routeManager.getPrimaryDefaultRouteInfo();
            final g = (info['gateway'] ?? '').trim();
            final inf = (info['interfaceName'] ?? '').trim();
            if (g.isNotEmpty) currentGateway = g;
            if (inf.isNotEmpty) currentIface = inf;
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
        throw const RouteConfigurationException(
          'Faltan gateway o interfaz para habilitar el túnel dividido. Usa "Detectar red actual" o completa los campos en Opciones avanzadas.',
        );
      }

      yield WorkflowState(
        step: ConnectionStep.splitTunnel,
        logMessage:
            'Paso 2/4 — Habilitando túnel dividido para ${sanitizedSubnets.length} subred(es)',
      );

      try {
        splitTunnelSetupAttempted = true;
        final splitMsg = await routeManager.enableSplitTunnel(
          hospitalSubnets: sanitizedSubnets,
          gateway: currentGateway,
          interfaceName: currentIface,
        );

        yield WorkflowState(
            step: ConnectionStep.splitTunnel, logMessage: splitMsg);
        splitTunnelEnabledThisAttempt = true;

        if (onSplitTunnelEnabled != null) {
          try {
            await onSplitTunnelEnabled(
              sanitizedSubnets,
              currentGateway,
              currentIface,
            );
          } catch (_) {
            // No interrumpir la conexión si falla el registro de limpieza.
          }
        }

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
      } on RouteConfigurationException catch (e) {
        const fallbackPlatforms = {
          TargetPlatform.android,
          TargetPlatform.iOS,
          TargetPlatform.macOS,
        };
        if (!fallbackPlatforms.contains(defaultTargetPlatform)) {
          rethrow;
        }
        var rolledBack = false;
        try {
          await routeManager.disableSplitTunnel();
          rolledBack = true;
        } catch (_) {
          // La limpieza es best-effort; en móvil o macOS puede no haber rutas.
        }
        if (rolledBack || !splitTunnelEnabledThisAttempt) {
          if (onSplitTunnelUnavailable != null) {
            try {
              await onSplitTunnelUnavailable();
            } catch (_) {
              // La UI ya no debe bloquear la siguiente conexión.
            }
          }
        }
        if (rolledBack &&
            splitTunnelEnabledThisAttempt &&
            onSplitTunnelRolledBack != null) {
          try {
            await onSplitTunnelRolledBack();
          } catch (_) {
            // El rollback de red ya se completó; el registro es secundario.
          }
        }
        splitTunnelEnabledThisAttempt = false;
        splitTunnelSetupAttempted = false;
        yield WorkflowState(
          step: ConnectionStep.preLaunch,
          logMessage: 'Túnel dividido no disponible en esta plataforma ($e). '
              'Se continuará usando las rutas del sistema; asegúrate de estar '
              'en la red del hospital.',
          isError: true,
        );
      }

      if (onSelectServer != null) {
        try {
          final selected = await onSelectServer();
          if (selected != null) {
            effectiveHost = selected.host;
            effectivePort = selected.port;
          }
        } catch (e) {
          yield WorkflowState(
            step: ConnectionStep.preLaunch,
            logMessage:
                'No se pudo seleccionar automáticamente el servidor ($e). Se usará el configurado.',
            isError: true,
          );
        }
      }

      final sanitizedHost =
          InputSanitizer.sanitizeHostname(effectiveHost, fieldName: 'Servidor RDP');
      final sanitizedPort = InputSanitizer.sanitizePort(
        effectivePort.toString(),
        fieldName: 'Puerto RDP',
      );

      yield const WorkflowState(
        step: ConnectionStep.preLaunch,
        logMessage: 'Paso 3/4 — Verificando alcance al destino y cliente RDP',
      );

      try {
        final addresses = await InternetAddress.lookup(sanitizedHost)
            .timeout(const Duration(seconds: 4));
        if (addresses.isNotEmpty) {
          yield WorkflowState(
            step: ConnectionStep.preLaunch,
            logMessage:
                'DNS resolvió $sanitizedHost a ${addresses.first.address}.',
          );
        }
      } on TimeoutException {
        yield const WorkflowState(
          step: ConnectionStep.preLaunch,
          logMessage:
              'La resolución DNS tardó más de 4s. Se continuará con la prueba de alcance.',
          isError: true,
        );
      } catch (e) {
        yield WorkflowState(
          step: ConnectionStep.preLaunch,
          logMessage:
              'No se pudo resolver DNS para $sanitizedHost ($e). Si el nombre es interno, conéctate a la red o DNS del hospital.',
          isError: true,
        );
      }

      final hostPing = await networkDiagnostics.ping(sanitizedHost);
      if (hostPing != null) {
        yield WorkflowState(
            step: ConnectionStep.preLaunch,
            logMessage: 'Host RDP $sanitizedHost responde en ${hostPing}ms.');
      } else {
        yield const WorkflowState(
          step: ConnectionStep.preLaunch,
          logMessage:
              'El host RDP no respondió a ICMP. Si el servidor bloquea ping, se intentará abrir RDP de todos modos.',
          isError: true,
        );
      }

      final tcpConnectTime =
          await networkDiagnostics.checkTcpPort(sanitizedHost, sanitizedPort);
      if (tcpConnectTime == null) {
        throw RdpTimeoutException(
          'No se pudo abrir el puerto TCP $sanitizedPort en $sanitizedHost. Revisa rutas, firewall o disponibilidad del servidor RDP.',
        );
      }
      yield WorkflowState(
          step: ConnectionStep.preLaunch,
          logMessage:
              'Puerto TCP $sanitizedPort accesible en ${tcpConnectTime}ms.');

      yield const WorkflowState(
          step: ConnectionStep.launchRdp,
          logMessage: 'Paso 4/4 — Lanzando conexión RDP');

      final available = await rdpLauncher.isRdpClientAvailable();
      if (!available) {
        throw const RdpLaunchException(
          'No hay un cliente RDP instalado. Instala o habilita Microsoft Remote Desktop Connection.',
        );
      }

      final ready = await rdpLauncher.preLaunch();
      if (!ready) {
        throw const RdpLaunchException(
          'No se encontró un manejador para rdp://. Instala o configura un cliente RDP compatible.',
        );
      }

      final launchResult = await rdpLauncher.launchRdp(
        host: sanitizedHost,
        port: sanitizedPort,
        username: sanitizedUser,
        domain: sanitizedDomain,
        profile: rdpProfile,
        measuredLatencyMs: tcpConnectTime,
      );

      yield WorkflowState(
          step: ConnectionStep.done,
          logMessage: launchResult,
          isFinished: true);
    } catch (e) {
      if (splitTunnelEnabledThisAttempt || splitTunnelSetupAttempted) {
        yield const WorkflowState(
          step: ConnectionStep.error,
          logMessage: 'Re-deshabilitando túnel dividido debido a error...',
        );
        try {
          await routeManager.disableSplitTunnel();
          if (onSplitTunnelRolledBack != null) {
            try {
              await onSplitTunnelRolledBack();
            } catch (_) {
              // El rollback de red ya se completó; el registro es secundario.
            }
          }
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
