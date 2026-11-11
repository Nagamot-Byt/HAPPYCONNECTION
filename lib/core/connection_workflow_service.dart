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
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:medlink_connect/features/ui/home_controller.dart'
    show ConnectionStep;

class WorkflowState {
  final ConnectionStep step;
  final String logMessage;
  final bool isError;
  final bool isFinished;
  final MedLinkErrorType? errorType;

  const WorkflowState({
    required this.step,
    required this.logMessage,
    this.isError = false,
    this.isFinished = false,
    this.errorType,
  });
}

typedef SelectedRdpTarget = ({String host, int port});

typedef HostCidrResolver = Future<List<String>> Function(String host);

/// Resolves [host] to IPv4 /32 CIDRs so the split tunnel can route the RDP
/// server through the hospital gateway without asking the user for subnets.
Future<List<String>> resolveHostCidrs(String host) async {
  final addresses =
      await InternetAddress.lookup(host).timeout(const Duration(seconds: 4));
  final seen = <String>{};
  for (final address in addresses) {
    if (address.type == InternetAddressType.IPv4) {
      seen.add('${address.address}/32');
    }
  }
  return seen.toList(growable: false);
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

  /// Overridable in tests to avoid real DNS lookups.
  HostCidrResolver hostCidrResolver = resolveHostCidrs;

  AppLocalizations? _l10n;

  void configureLocalizations(AppLocalizations l10n) {
    _l10n = l10n;
  }

  AppLocalizations get _t {
    final l10n = _l10n;
    if (l10n == null) {
      throw StateError(
          'ConnectionWorkflowService.localizations not configured');
    }
    return l10n;
  }

  bool get _requiresNetworkConfig =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;

  bool get _supportsWifi =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;

  bool _sameInterfaceName(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  Future<List<String>> _resolveHostSubnets(String host) async {
    try {
      return await hostCidrResolver(host);
    } catch (_) {
      return const [];
    }
  }

  Stream<WorkflowState> connect({
    List<String> subnets = const [],
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

    yield WorkflowState(
      step: ConnectionStep.diagnostics,
      logMessage: _t.logWorkflowStart,
    );

    try {
      var effectiveHost = host;
      var effectivePort = resolvedPort;

      // Validate inputs using InputSanitizer
      final sanitizedSubnets = InputSanitizer.sanitizeSubnets(
        subnets,
        fieldName: _t.hospitalSubnets,
        allowEmpty: true,
      );
      final sanitizedGateway = gateway.trim().isEmpty
          ? ''
          : InputSanitizer.sanitizeIpv4(gateway, fieldName: _t.gateway);
      final sanitizedIface = iface.trim().isEmpty
          ? ''
          : InputSanitizer.sanitizeInterfaceName(iface,
              fieldName: _t.fieldInterface);
      final sanitizedUser = user.trim().isEmpty
          ? null
          : InputSanitizer.sanitizeRdpCredential(user,
              fieldName: _t.rdpUsername);
      final sanitizedDomain = domain.trim().isEmpty
          ? null
          : InputSanitizer.sanitizeRdpCredential(domain,
              fieldName: _t.rdpDomain);

      String currentGateway = sanitizedGateway;
      String currentIface = sanitizedIface;

      if (selectedWifi.isNotEmpty && !_supportsWifi) {
        yield WorkflowState(
          step: ConnectionStep.diagnostics,
          logMessage: _t.logWorkflowWifiUnavailable,
        );
      }

      if (_supportsWifi && wifiManager != null && selectedWifi.isNotEmpty) {
        try {
          final sanitizedSsid = InputSanitizer.sanitizeSsid(selectedWifi);
          final targetSsid = sanitizedSsid;

          var alreadyConnected = false;
          try {
            final info = await wifiManager!.getCurrentConnectionInfo();
            alreadyConnected = info.ssid == targetSsid;
            if (alreadyConnected) {
              currentGateway = info.gateway.trim();
              currentIface = info.interfaceName.trim();
            }
          } on MissingPluginException {
            rethrow;
          } catch (_) {
            // Si la plataforma no puede consultar el Wi-Fi, se intenta conectar.
          }

          if (alreadyConnected) {
            yield WorkflowState(
              step: ConnectionStep.diagnostics,
              logMessage: _t.logWorkflowAlreadyConnected(targetSsid),
            );
          } else {
            yield WorkflowState(
              step: ConnectionStep.diagnostics,
              logMessage: _t.logWorkflowStepWifi,
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
                if (info.ssid != targetSsid) continue;
                final g = info.gateway.trim();
                final inf = info.interfaceName.trim();
                if (_requiresNetworkConfig && (g.isEmpty || inf.isEmpty)) {
                  continue;
                }
                currentGateway = g;
                currentIface = inf;
                confirmed = true;
                yield WorkflowState(
                  step: ConnectionStep.diagnostics,
                  logMessage: _t.logWorkflowWifiConnected(
                    targetSsid,
                    currentGateway,
                    currentIface,
                  ),
                );
                break;
              } catch (_) {
                // Reintentar hasta confirmar la red objetivo.
              }
            }

            if (!confirmed) {
              final detail = connectResult.trim();
              throw WifiConnectionException(
                detail.isEmpty
                    ? _t.logWifiNotConfirmed(targetSsid)
                    : _t.logWifiNotConfirmedWithResponse(targetSsid, detail),
              );
            }
          }
        } on MissingPluginException {
          yield WorkflowState(
            step: ConnectionStep.diagnostics,
            logMessage: _t.logWorkflowWifiUnavailable,
            isError: true,
          );
        }

        if (currentGateway.isEmpty || currentIface.isEmpty) {
          try {
            final knownIface =
                currentIface.isNotEmpty ? currentIface : sanitizedIface;
            final info = await routeManager.getPrimaryDefaultRouteInfo();
            final g = (info['gateway'] ?? '').trim();
            final inf = (info['interfaceName'] ?? '').trim();
            final sameInterface = knownIface.isEmpty ||
                inf.isEmpty ||
                _sameInterfaceName(inf, knownIface);
            if (sameInterface) {
              if (g.isNotEmpty) currentGateway = g;
              if (inf.isNotEmpty) currentIface = inf;
            }
          } catch (_) {}
        }
        if (currentGateway.isEmpty || currentIface.isEmpty) {
          yield WorkflowState(
            step: ConnectionStep.diagnostics,
            logMessage: _t.logWorkflowNoAutoNetwork,
            isError: true,
          );
        }
      } else {
        currentGateway = sanitizedGateway;
        currentIface = sanitizedIface;
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
            logMessage: _t.logSelectBestServerError('$e'),
            isError: true,
          );
        }
      }

      yield WorkflowState(
        step: ConnectionStep.splitTunnel,
        logMessage: _t.logWorkflowStepPrepare,
      );

      if (_requiresNetworkConfig &&
          (currentGateway.isEmpty || currentIface.isEmpty)) {
        throw RouteConfigurationException(_t.logMissingGatewayInterfaceHint);
      }

      var effectiveSubnets = sanitizedSubnets;
      if (effectiveSubnets.isEmpty &&
          _requiresNetworkConfig &&
          effectiveHost.trim().isNotEmpty) {
        final autoSubnets = await _resolveHostSubnets(effectiveHost.trim());
        if (autoSubnets.isNotEmpty) {
          try {
            effectiveSubnets = InputSanitizer.sanitizeSubnets(
              autoSubnets,
              fieldName: _t.hospitalSubnets,
              allowEmpty: true,
            );
            yield WorkflowState(
              step: ConnectionStep.splitTunnel,
              logMessage: _t.logWorkflowAutoRoutes(
                effectiveHost.trim(),
                effectiveSubnets.join(', '),
              ),
            );
          } on ArgumentError {
            effectiveSubnets = const [];
          }
        }
      }

      if (effectiveSubnets.isEmpty) {
        yield WorkflowState(
          step: ConnectionStep.splitTunnel,
          logMessage: _t.logWorkflowNoSubnets,
        );
      } else {
        final trackedSubnets = <String>[];
        if (onSplitTunnelEnabled != null) {
          for (final subnet in effectiveSubnets) {
            try {
              final missingRoutes = await routeManager.verifyRoutes(
                hospitalSubnets: [subnet],
                gateway: currentGateway,
                interfaceName: currentIface,
              );
              if (missingRoutes.isNotEmpty) trackedSubnets.add(subnet);
            } catch (_) {
              // If the pre-check fails, do not persist a cleanup record:
              // deleting a route that already existed is worse than leaving
              // one of ours behind after a crash.
            }
          }
        }

        yield WorkflowState(
          step: ConnectionStep.splitTunnel,
          logMessage: _t.logWorkflowStepTunnel(effectiveSubnets.length),
        );

        try {
          splitTunnelSetupAttempted = true;
          final splitMsg = await routeManager.enableSplitTunnel(
            hospitalSubnets: effectiveSubnets,
            gateway: currentGateway,
            interfaceName: currentIface,
          );

          yield WorkflowState(
              step: ConnectionStep.splitTunnel, logMessage: splitMsg);
          splitTunnelEnabledThisAttempt = true;

          if (onSplitTunnelEnabled != null) {
            try {
              await onSplitTunnelEnabled(
                trackedSubnets,
                currentGateway,
                currentIface,
              );
            } catch (_) {
              // No interrumpir la conexión si falla el registro de limpieza.
            }
          }

          await Future<void>.delayed(const Duration(milliseconds: 600));
          final missingRoutes = await routeManager.verifyRoutes(
            hospitalSubnets: effectiveSubnets,
            gateway: currentGateway,
            interfaceName: currentIface,
          );

          if (missingRoutes.isNotEmpty) {
            throw RouteConfigurationException(
              _t.errorRoutesMissing(missingRoutes.join(', ')),
            );
          }

          yield WorkflowState(
              step: ConnectionStep.preLaunch,
              logMessage: _t.logWorkflowRoutesVerified);
        } on MedLinkException catch (e) {
          // Android reports missing root as PrivilegeRequiredException; iOS and
          // macOS report unsupported route changes as RouteConfigurationException.
          // All three platforms can still launch RDP over the existing network.
          final isFallbackError = e is RouteConfigurationException ||
              e is PrivilegeRequiredException;
          const fallbackPlatforms = {
            TargetPlatform.android,
            TargetPlatform.iOS,
            TargetPlatform.macOS,
          };
          if (!isFallbackError ||
              !fallbackPlatforms.contains(defaultTargetPlatform)) {
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
            logMessage: _t.logWorkflowTunnelUnavailable('$e'),
            isError: true,
          );
        }
      }

      final sanitizedHost = InputSanitizer.sanitizeHostname(effectiveHost,
          fieldName: _t.rdpServer);
      final sanitizedPort = InputSanitizer.sanitizePort(
        effectivePort.toString(),
        fieldName: _t.rdpPort,
      );

      yield WorkflowState(
        step: ConnectionStep.preLaunch,
        logMessage: _t.logWorkflowStepVerify,
      );

      try {
        final addresses = await InternetAddress.lookup(sanitizedHost)
            .timeout(const Duration(seconds: 4));
        if (addresses.isNotEmpty) {
          yield WorkflowState(
            step: ConnectionStep.preLaunch,
            logMessage: _t.logWorkflowDnsResolved(
              sanitizedHost,
              addresses.first.address,
            ),
          );
        }
      } on TimeoutException {
        yield WorkflowState(
          step: ConnectionStep.preLaunch,
          logMessage: _t.logWorkflowDnsTimeout,
          isError: true,
        );
      } catch (e) {
        yield WorkflowState(
          step: ConnectionStep.preLaunch,
          logMessage: _t.logWorkflowDnsError(sanitizedHost, '$e'),
          isError: true,
        );
      }

      final hostPing = await networkDiagnostics.ping(sanitizedHost);
      if (hostPing != null) {
        yield WorkflowState(
            step: ConnectionStep.preLaunch,
            logMessage: _t.logWorkflowIcmpOk(sanitizedHost, hostPing));
      } else {
        final probeError = networkDiagnostics.lastProbeError;
        yield WorkflowState(
          step: ConnectionStep.preLaunch,
          logMessage: '${_t.logWorkflowIcmpFailed}'
              '${probeError == null ? '' : ' ${_t.logCauseLabel(probeError)}'}',
          isError: true,
        );
      }

      final tcpConnectTime =
          await networkDiagnostics.checkTcpPort(sanitizedHost, sanitizedPort);
      if (tcpConnectTime == null) {
        final probeError = networkDiagnostics.lastProbeError;
        throw RdpTimeoutException(
          '${_t.errorTcpUnreachable(sanitizedPort, sanitizedHost)}'
          '${probeError == null ? '' : ' ${_t.logCauseLabel(probeError)}'}',
        );
      }
      yield WorkflowState(
          step: ConnectionStep.preLaunch,
          logMessage: _t.logWorkflowTcpOpen(sanitizedPort, tcpConnectTime));

      yield WorkflowState(
          step: ConnectionStep.launchRdp, logMessage: _t.logWorkflowStepLaunch);

      final available = await rdpLauncher.isRdpClientAvailable();
      if (!available) {
        throw RdpLaunchException(_t.errorRdpClientMissing);
      }

      final ready = await rdpLauncher.preLaunch();
      if (!ready) {
        throw RdpLaunchException(_t.errorRdpHandlerMissing);
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
        yield WorkflowState(
          step: ConnectionStep.error,
          logMessage: _t.logWorkflowRollbackStart,
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
          yield WorkflowState(
            step: ConnectionStep.error,
            logMessage: _t.logWorkflowRollbackDone,
          );
        } catch (disableError) {
          yield WorkflowState(
            step: ConnectionStep.error,
            logMessage: _t.logWorkflowRollbackError('$disableError'),
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
          logMessage: _t.logWorkflowError(errorMsg),
          isError: true,
          isFinished: true,
          errorType: e is MedLinkException ? e.type : MedLinkErrorType.unknown);
    }
  }
}
