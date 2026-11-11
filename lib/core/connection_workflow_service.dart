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

typedef GatewayDnsResolver = Future<List<String>> Function(
    String host, String gateway);

int _ipv4ToInt(String address) {
  final parts = address.split('.');
  var value = 0;
  for (final part in parts) {
    value = (value << 8) | (int.tryParse(part) ?? 0);
  }
  return value;
}

/// Returns true when [cidr] already covers [address] (a /32 or host).
bool _cidrCovers(String cidr, String address) {
  final cidrParts = cidr.split('/');
  final addressParts = address.split('/');
  final cidrPrefix =
      int.tryParse(cidrParts.length > 1 ? cidrParts[1] : '32') ?? 32;
  final addressPrefix =
      int.tryParse(addressParts.length > 1 ? addressParts[1] : '32') ?? 32;
  if (cidrPrefix > addressPrefix) return false;
  final mask = (0xFFFFFFFF << (32 - cidrPrefix)) & 0xFFFFFFFF;
  return (_ipv4ToInt(cidrParts[0]) & mask) ==
      (_ipv4ToInt(addressParts[0]) & mask);
}

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

/// Resolves [host] through the hospital gateway's DNS server.
///
/// The split tunnel is not installed yet when routes are derived, so the
/// system resolver may be unable to reach an internal-only DNS server. Asking
/// the gateway directly (via `nslookup`) works as long as the Wi-Fi is already
/// associated with the hospital network.
Future<List<String>> resolveHostCidrsViaGateway(
    String host, String gateway) async {
  final target = host.trim();
  final server = gateway.trim();
  if (target.isEmpty || server.isEmpty) return const [];

  final args = Platform.isWindows
      ? <String>['-timeout=2', '-retry=1', target, server]
      : <String>['+timeout=2', '+tries=1', target, server];
  try {
    final result =
        await Process.run('nslookup', args).timeout(const Duration(seconds: 5));
    if (result.exitCode != 0) return const [];
    final ipv4 = RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b');
    final seen = <String>{};
    var inAnswer = false;
    for (final raw in '${result.stdout}'.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      final lower = line.toLowerCase();
      if (lower.startsWith('name:') || lower.startsWith('nombre:')) {
        inAnswer = true;
      }
      if (!inAnswer) continue;
      for (final match in ipv4.allMatches(line)) {
        final value = match.group(0)!;
        if (value == server) continue;
        try {
          InputSanitizer.sanitizeIpv4(value);
        } on ArgumentError {
          continue;
        }
        seen.add('$value/32');
      }
    }
    return seen.toList(growable: false);
  } catch (_) {
    return const [];
  }
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

  /// Overridable in tests to avoid spawning `nslookup`.
  GatewayDnsResolver gatewayDnsResolver = resolveHostCidrsViaGateway;

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

  Future<List<String>> _resolveHostSubnets(
    String host, {
    String? gateway,
  }) async {
    final target = host.trim();
    try {
      final literal = InputSanitizer.sanitizeIpv4(target);
      return ['$literal/32'];
    } on ArgumentError {
      // Not a literal IPv4 address; resolve it below.
    }
    try {
      final direct = await hostCidrResolver(target);
      if (direct.isNotEmpty) return direct;
    } catch (_) {
      // Fall through to the gateway DNS fallback.
    }
    final server = gateway?.trim() ?? '';
    if (server.isEmpty) return const [];
    try {
      return await gatewayDnsResolver(target, server);
    } catch (_) {
      return const [];
    }
  }

  Future<List<String>> _missingForTracking(
    List<String> subnets,
    String gateway,
    String interfaceName,
  ) async {
    final tracked = <String>[];
    for (final subnet in subnets) {
      try {
        final missing = await routeManager.verifyRoutes(
          hospitalSubnets: [subnet],
          gateway: gateway,
          interfaceName: interfaceName,
        );
        if (missing.isNotEmpty) tracked.add(subnet);
      } catch (_) {
        // If the pre-check fails, do not persist a cleanup record: deleting a
        // route that already existed is worse than leaving one behind.
      }
    }
    return tracked;
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
    List<String> candidateHosts = const [],
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

      yield WorkflowState(
        step: ConnectionStep.splitTunnel,
        logMessage: _t.logWorkflowStepPrepare,
      );

      if (_requiresNetworkConfig &&
          (currentGateway.isEmpty || currentIface.isEmpty)) {
        throw RouteConfigurationException(_t.logMissingGatewayInterfaceHint);
      }

      // Routes must exist before the auto-selection probes run, otherwise the
      // probes cannot reach the hospital servers. When selection is enabled we
      // pre-route every candidate so the chosen server is already covered.
      final hostsToRoute = <String>[];
      void addHost(String value) {
        final trimmed = value.trim();
        if (trimmed.isNotEmpty && !hostsToRoute.contains(trimmed)) {
          hostsToRoute.add(trimmed);
        }
      }

      if (onSelectServer != null) {
        addHost(host);
        for (final candidate in candidateHosts) {
          addHost(candidate);
        }
      } else {
        addHost(effectiveHost);
      }

      var effectiveSubnets = sanitizedSubnets;
      if (effectiveSubnets.isEmpty &&
          _requiresNetworkConfig &&
          hostsToRoute.isNotEmpty) {
        final resolved = await Future.wait(
          hostsToRoute.map(
            (candidate) =>
                _resolveHostSubnets(candidate, gateway: currentGateway),
          ),
        );
        final autoSubnets = <String>{};
        for (final subnets in resolved) {
          autoSubnets.addAll(subnets);
        }
        if (autoSubnets.isNotEmpty) {
          try {
            effectiveSubnets = InputSanitizer.sanitizeSubnets(
              autoSubnets.toList(growable: false),
              fieldName: _t.hospitalSubnets,
              allowEmpty: true,
            );
            yield WorkflowState(
              step: ConnectionStep.splitTunnel,
              logMessage: _t.logWorkflowAutoRoutes(
                hostsToRoute.join(', '),
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
          // Android reports missing root as PrivilegeRequiredException; iOS,
          // macOS, Windows and Linux report unsupported route changes or
          // missing elevation as RouteConfigurationException /
          // PrivilegeRequiredException. All of them can still launch RDP over
          // the existing network if the server is reachable.
          final isFallbackError = e is RouteConfigurationException ||
              e is PrivilegeRequiredException;
          const fallbackPlatforms = {
            TargetPlatform.android,
            TargetPlatform.iOS,
            TargetPlatform.macOS,
            TargetPlatform.windows,
            TargetPlatform.linux,
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

      // Selection runs after the tunnel is up so the probes reach the hospital
      // servers through the newly installed routes.
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

        // The chosen host may resolve to a different address than the
        // pre-routed candidates (multi-A / round-robin). Make sure its /32
        // routes exist before probing and launching RDP.
        if (_requiresNetworkConfig &&
            effectiveSubnets.isNotEmpty &&
            effectiveHost.trim().isNotEmpty) {
          final finalSubnets = await _resolveHostSubnets(
            effectiveHost.trim(),
            gateway: currentGateway,
          );
          final missing = finalSubnets
              .where(
                (subnet) => !effectiveSubnets
                    .any((existing) => _cidrCovers(existing, subnet)),
              )
              .toList(growable: false);
          if (missing.isNotEmpty) {
            final tracked = await _missingForTracking(
                missing, currentGateway, currentIface);
            var added = false;
            try {
              final splitMsg = await routeManager.enableSplitTunnel(
                hospitalSubnets: missing,
                gateway: currentGateway,
                interfaceName: currentIface,
              );
              added = true;
              splitTunnelEnabledThisAttempt = true;
              effectiveSubnets = [...effectiveSubnets, ...missing];
              yield WorkflowState(
                  step: ConnectionStep.splitTunnel, logMessage: splitMsg);
              yield WorkflowState(
                step: ConnectionStep.splitTunnel,
                logMessage: _t.logWorkflowFinalRoutes(
                  effectiveHost.trim(),
                  missing.join(', '),
                ),
              );
              if (onSplitTunnelEnabled != null) {
                try {
                  await onSplitTunnelEnabled(
                    tracked,
                    currentGateway,
                    currentIface,
                  );
                } catch (_) {
                  // El registro de limpieza es secundario.
                }
              }
              await Future<void>.delayed(const Duration(milliseconds: 600));
              final stillMissing = await routeManager.verifyRoutes(
                hospitalSubnets: missing,
                gateway: currentGateway,
                interfaceName: currentIface,
              );
              if (stillMissing.isNotEmpty) {
                throw RouteConfigurationException(
                  _t.errorRoutesMissing(stillMissing.join(', ')),
                );
              }
            } catch (e) {
              if (added) {
                try {
                  await routeManager.disableSplitTunnel();
                  splitTunnelEnabledThisAttempt = false;
                  effectiveSubnets = const [];
                  if (onSplitTunnelRolledBack != null) {
                    try {
                      await onSplitTunnelRolledBack();
                    } catch (_) {
                      // El rollback de red ya se completó.
                    }
                  }
                } catch (_) {
                  // La limpieza es best-effort.
                }
              }
              yield WorkflowState(
                step: ConnectionStep.preLaunch,
                logMessage: _t.logWorkflowTunnelUnavailable('$e'),
                isError: true,
              );
            }
          }
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
