import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:medlink_connect/core/connection_workflow_service.dart';
import 'package:medlink_connect/core/exceptions.dart';
import 'package:medlink_connect/core/input_sanitizer.dart';
import 'package:medlink_connect/core/network_diagnostics.dart';
import 'package:medlink_connect/core/rdp_launcher.dart';
import 'package:medlink_connect/core/route_manager.dart';
import 'package:medlink_connect/core/settings_storage.dart';
import 'package:medlink_connect/core/wifi_manager.dart';
import 'package:medlink_connect/features/ui/error_guidance.dart';
import 'package:medlink_connect/features/ui/home_models.dart';
import 'package:medlink_connect/features/ui/server_preset_selector.dart';
import 'package:medlink_connect/features/wifi/wifi_connection_coordinator.dart';

export 'package:medlink_connect/features/ui/home_models.dart'
    show ConnectionLogEntry, ServerPreset;

enum ConnectionStep {
  idle,
  diagnostics,
  splitTunnel,
  preLaunch,
  launchRdp,
  done,
  error,
}

class HomeController extends ChangeNotifier {
  final SettingsStorage? settings;
  final WifiManager? wifiManager;
  final RouteManager routeManager;
  final NetworkDiagnostics networkDiagnostics;
  final RdpLauncher rdpLauncher;
  final ConnectionWorkflowService workflowService;
  final AppLocalizations l10n;

  HomeController({
    this.settings,
    this.wifiManager,
    required this.routeManager,
    required this.networkDiagnostics,
    required this.rdpLauncher,
    required this.workflowService,
    required this.l10n,
  }) : errorGuidance = ErrorGuidanceResolver(l10n) {
    workflowService.configureLocalizations(l10n);
  }

  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool get _isWifiSupported =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;

  bool get wifiSupported => _wifi.isSupported;

  bool get rdpProfileSupported =>
      defaultTargetPlatform == TargetPlatform.windows;

  bool get _supportsRouteChanges =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.android;

  bool get _requiresNetworkConfig =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;

  bool _loaded = false;
  bool get loaded => _loaded;

  bool _busy = false;
  bool get busy => _busy;

  ConnectionStep _step = ConnectionStep.idle;
  ConnectionStep get step => _step;

  bool _splitTunnelActive = false;
  bool get splitTunnelActive => _splitTunnelActive;

  final ConnectionLogStore _logStore = ConnectionLogStore();
  List<ConnectionLogEntry> get logEntries => _logStore.entries;
  List<String> get logs => _logStore.formatted;

  late final WifiConnectionCoordinator _wifi = WifiConnectionCoordinator(
    wifiManager: wifiManager,
    l10n: l10n,
    onLog: log,
    onChanged: _notify,
    currentGatewayAndInterface: () => (
      gateway: gatewayCtrl.text,
      iface: ifaceCtrl.text,
    ),
    applyGatewayAndInterface: (gateway, iface) {
      gatewayCtrl.text = gateway;
      ifaceCtrl.text = iface;
    },
  );

  late final ServerPresetSelector _presetSelector = ServerPresetSelector(
    networkDiagnostics: networkDiagnostics,
    l10n: l10n,
    onLog: log,
    onApply: (preset) {
      rdpHostCtrl.text = preset.host;
      rdpPortCtrl.text = preset.port.toString();
    },
  );

  String? _guidanceTitle;
  String? get guidanceTitle => _guidanceTitle;

  List<String> _guidanceBullets = [];
  List<String> get guidanceBullets => List.unmodifiable(_guidanceBullets);

  bool _guidanceIsError = false;
  bool get guidanceIsError => _guidanceIsError;

  final TextEditingController subnetsCtrl = TextEditingController();
  final TextEditingController gatewayCtrl = TextEditingController();
  final TextEditingController ifaceCtrl = TextEditingController();
  final TextEditingController rdpHostCtrl = TextEditingController();
  final TextEditingController rdpPortCtrl = TextEditingController();
  final TextEditingController rdpUserCtrl = TextEditingController();
  final TextEditingController rdpDomainCtrl = TextEditingController();
  final TextEditingController manualWifiCtrl = TextEditingController();
  final TextEditingController wifiPasswordCtrl = TextEditingController();

  String _rdpProfile = 'adaptive';
  String get rdpProfile => _rdpProfile;
  set rdpProfile(String value) {
    _rdpProfile = value;
    _notify();
  }

  bool _preferMostStableServer = true;
  bool get preferMostStableServer => _preferMostStableServer;
  set preferMostStableServer(bool value) {
    _preferMostStableServer = value;
    _notify();
  }

  String get selectedServerPresetId => _presetSelector.selectedPresetId;
  set selectedServerPresetId(String value) {
    _presetSelector.selectedPresetId = value;
    _notify();
  }

  List<ServerPreset> get serverPresets => _presetSelector.presets;
  set serverPresets(List<ServerPreset> value) {
    _presetSelector.presets = value;
    _notify();
  }

  List<String> get wifiNetworks => _wifi.networks;

  bool get wifiNetworksLoading => _wifi.networksLoading;

  String? get wifiScanError => _wifi.scanError;

  String? get selectedWifiSsid => _wifi.selectedSsid;
  set selectedWifiSsid(String? value) {
    _wifi.selectedSsid = value;
    _notify();
  }

  String get currentWifiSsid => _wifi.currentSsid;

  String get manualWifiOption => WifiConnectionCoordinator.manualWifiOption;

  void log(String message, {bool isError = false}) {
    _logStore.add(message, isError: isError);
    _notify();
  }

  void clearLogs() {
    _logStore.clear();
    _notify();
  }

  void setGuidance(String title,
      {List<String> bullets = const [], bool isError = false}) {
    _guidanceTitle = title;
    _guidanceBullets = bullets;
    _guidanceIsError = isError;
    _notify();
  }

  void clearGuidance() {
    _guidanceTitle = null;
    _guidanceBullets = [];
    _guidanceIsError = false;
    _notify();
  }

  void setReadyGuidance() {
    setGuidance(
      l10n.guidanceReadyTitle,
      bullets: [
        l10n.guidanceReadyBullet1,
        l10n.guidanceReadyBullet2,
        l10n.guidanceReadyBullet3,
      ],
    );
  }

  final ErrorGuidanceResolver errorGuidance;

  void setErrorGuidance(Object error) {
    setErrorGuidanceType(errorGuidance.classify(error));
  }

  void setErrorGuidanceType(MedLinkErrorType type) {
    final guidance = errorGuidance.resolveType(type);
    setGuidance(
      guidance.title,
      bullets: guidance.bullets,
      isError: true,
    );
  }

  Future<void> init() async {
    _logStore.clear();
    log(l10n.logStartup);
    try {
      await _loadSettings();
    } catch (e) {
      log(l10n.logLoadSettingsError('$e'), isError: true);
    }
    try {
      await _cleanupStaleSplitTunnel();
    } catch (e) {
      log(l10n.logCleanupSettingsError('$e'), isError: true);
    }
    _loaded = true;
    _notify();
    setReadyGuidance();

    // We can run these without awaiting init
    refreshWifiNetworks(silent: true);
    syncCurrentWifiInfo(silent: true, overwrite: false);
  }

  Future<void> _persistSplitTunnelCleanup({
    required List<String> subnets,
    required String gateway,
    required String interfaceName,
  }) async {
    final s = settings;
    if (s == null) return;
    await s.setPendingSplitTunnelCleanup(
      subnets: subnets,
      gateway: gateway,
      interfaceName: interfaceName,
    );
  }

  Future<bool> _cleanupStaleSplitTunnel() async {
    final s = settings;
    if (s == null) return true;
    final pending = s.pendingSplitTunnelCleanup;
    if (pending == null) return true;

    log(l10n.logStaleTunnelFound);
    final failures = <String>[];
    for (final subnet in pending.subnets) {
      try {
        await routeManager.removeRoute(
          destinationCidr: subnet,
          gateway: pending.gateway,
          interfaceName: pending.interfaceName,
        );
      } catch (e) {
        failures.add('$subnet ($e)');
      }
    }
    if (failures.isEmpty) {
      await s.clearPendingSplitTunnelCleanup();
      _splitTunnelActive = false;
      log(l10n.logStaleRoutesRemoved);
      return true;
    }
    log(
      l10n.logStaleRoutesFailed(failures.join(', ')),
      isError: true,
    );
    return false;
  }

  Future<void> _loadSettings() async {
    final s = settings;
    if (s == null) {
      log(l10n.logStorageUnavailable);
      return;
    }
    await s.init();

    subnetsCtrl.text = s.hospitalSubnetsAsText;
    gatewayCtrl.text = s.gateway;
    ifaceCtrl.text = s.interfaceName;
    rdpHostCtrl.text = s.rdpHost;
    rdpPortCtrl.text = s.rdpPort.toString();
    rdpUserCtrl.text = s.rdpUsername;
    rdpDomainCtrl.text = s.rdpDomain;
    rdpProfile = s.rdpProfile;
    _preferMostStableServer = s.preferMostStableServer;
    selectedWifiSsid = s.wifiSsid.isEmpty ? null : s.wifiSsid;
    manualWifiCtrl.text = s.wifiSsid;
    _presetSelector.selectedPresetId = s.selectedServerPresetId;

    _presetSelector.presets = ServerPresetSelector.hospitalCatalog(l10n);
    _presetSelector.keepSelectionValid();
  }

  Future<void> saveSettings() async {
    final s = settings;
    if (s == null) return;

    s.hospitalSubnetsAsText = subnetsCtrl.text;
    s.gateway = gatewayCtrl.text;
    s.interfaceName = ifaceCtrl.text;
    s.rdpHost = rdpHostCtrl.text;
    s.rdpPort = int.tryParse(rdpPortCtrl.text) ?? 3389;
    s.rdpUsername = rdpUserCtrl.text;
    s.rdpDomain = rdpDomainCtrl.text;
    s.rdpProfile = rdpProfile;
    s.preferMostStableServer = preferMostStableServer;

    s.wifiSsid = resolvedWifiSsid();
    s.selectedServerPresetId = selectedServerPresetId;
    await s.save();
  }

  Future<void> _saveSettingsSafely() async {
    try {
      await saveSettings();
    } catch (e) {
      log(l10n.logSaveSettingsError('$e'), isError: true);
    }
  }

  String resolvedWifiSsid() => _wifi.resolveSsid(manualWifiCtrl.text);

  void selectManualWifi() {
    if (_wifi.selectManual()) {
      _notify();
    }
  }

  Future<void> refreshWifiNetworks({bool silent = false}) {
    return _wifi.refreshNetworks(silent: silent);
  }

  Future<WifiConnectionInfo?> syncCurrentWifiInfo({
    bool silent = false,
    bool overwrite = true,
  }) {
    return _wifi.syncCurrentInfo(silent: silent, overwrite: overwrite);
  }

  // --- Extracted Methods ---

  String friendlyRdpProfile(String value) {
    return switch (value) {
      'stable' => l10n.profileStable,
      'speed' => l10n.profileSpeed,
      _ => l10n.profileAdaptive,
    };
  }

  String selectAdaptiveRdpProfile(int? latencyMs) {
    if (rdpProfile != 'adaptive') return rdpProfile;
    if (latencyMs == null) return 'adaptive';
    if (latencyMs >= 140) return 'stable';
    if (latencyMs <= 60) return 'speed';
    return 'adaptive';
  }

  ServerPreset? presetById(String id) => _presetSelector.presetById(id);

  void applyServerPreset(ServerPreset preset, {bool announce = true}) {
    _presetSelector.applyPreset(preset);
    _notify();
    if (announce) {
      log(l10n.logPresetApplied(preset.label, preset.host));
      _notify();
    }
  }

  Future<ServerPreset?> diagnoseBestServerPreset({
    bool updateGuidance = true,
  }) async {
    final best = await _presetSelector.diagnoseBest(apply: updateGuidance);
    if (updateGuidance && best != null) {
      _notify();
    }
    return best;
  }

  Future<void> connectWifiOnly() async {
    if (_busy) return;
    clearGuidance();
    _busy = true;
    _notify();
    try {
      final connected = await connectSelectedWifi(requireSelection: true);
      if (connected) {
        // Reintentar obtener gateway/interfaz si faltan
        if (gatewayCtrl.text.trim().isEmpty || ifaceCtrl.text.trim().isEmpty) {
          await syncCurrentWifiInfo(silent: false);
        }
        setGuidance(
          l10n.guidanceWifiReadyTitle,
          bullets: [
            l10n.guidanceWifiReadyBullet1,
            gatewayCtrl.text.trim().isEmpty
                ? l10n.gatewayPending
                : l10n.gatewayValue(gatewayCtrl.text.trim()),
            ifaceCtrl.text.trim().isEmpty
                ? l10n.interfacePending
                : l10n.interfaceValue(ifaceCtrl.text.trim()),
            l10n.guidanceWifiReadyBullet4,
          ],
        );
        await saveSettings();
      } else {
        setGuidance(
          l10n.guidanceWifiFailedTitle,
          bullets: [
            l10n.guidanceWifiFailedBullet1,
            l10n.guidanceWifiFailedBullet2,
            l10n.guidanceWifiFailedBullet3,
            l10n.guidanceWifiFailedBullet4,
          ],
          isError: true,
        );
      }
    } catch (e) {
      log(l10n.logWifiError('$e'), isError: true);
      setErrorGuidance(e);
    } finally {
      wifiPasswordCtrl.clear();
      _busy = false;
      _notify();
    }
  }

  Future<WifiConnectionInfo?> waitForTargetWifiConnection(String ssid) {
    return _wifi.waitForTargetConnection(ssid);
  }

  Future<bool> connectSelectedWifi({required bool requireSelection}) async {
    if (!wifiSupported) {
      if (requireSelection) {
        log(l10n.logWorkflowWifiUnavailable, isError: true);
      }
      return false;
    }
    final rawWifi = resolvedWifiSsid();
    if (rawWifi.isEmpty) {
      if (requireSelection) {
        log(l10n.logNoWifiSelected, isError: true);
      }
      return false;
    }
    final String selectedWifi;
    try {
      selectedWifi = InputSanitizer.sanitizeSsid(
        rawWifi,
        fieldName: l10n.wifiNetworkName,
      );
    } on ArgumentError catch (e) {
      log(
        l10n.logInvalidConfiguration(l10n.wifiNetworkName, '$e'),
        isError: true,
      );
      return false;
    }
    final password = wifiPasswordCtrl.text;
    log(l10n.logConnectingWifi(selectedWifi));
    if (wifiManager != null) {
      final res =
          await wifiManager!.connect(ssid: selectedWifi, password: password);
      // La respuesta puede ser solo "solicitud enviada"; la fuente de verdad
      // es que el sistema reporte la SSID objetivo.
      final confirmed = await waitForTargetWifiConnection(selectedWifi);
      if (confirmed == null) {
        log(
          res.trim().isEmpty
              ? l10n.logWifiNotConfirmed(selectedWifi)
              : l10n.logWifiNotConfirmedWithResponse(selectedWifi, res),
          isError: true,
        );
        return false;
      }
      await syncCurrentWifiInfo(silent: true);
      // Intento adicional para obtener gateway/interfaz
      for (var i = 0;
          i < 6 &&
              (gatewayCtrl.text.trim().isEmpty ||
                  ifaceCtrl.text.trim().isEmpty);
          i++) {
        await Future<void>.delayed(Duration(milliseconds: 800 + i * 200));
        await syncCurrentWifiInfo(silent: true);
      }
      return true;
    }
    return false;
  }

  List<String> parseSubnets() {
    return subnetsCtrl.text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> warnIfDefaultRouteUsesHospitalInterface(
    String hospitalInterface,
  ) async {
    try {
      final info = await routeManager.getPrimaryDefaultRouteInfo();
      final defaultInterface = (info['interfaceName'] ?? '').trim();
      final defaultGateway = (info['gateway'] ?? '').trim();
      if (defaultInterface.isEmpty) return;
      if (defaultInterface.toLowerCase() != hospitalInterface.toLowerCase()) {
        return;
      }
      log(
        defaultGateway.isEmpty
            ? l10n.logDefaultRouteWarning(defaultInterface)
            : l10n.logDefaultRouteWarningWithGateway(
                defaultInterface,
                defaultGateway,
              ),
        isError: true,
      );
    } catch (_) {
      // Best-effort warning only.
    }
  }

  int parsePort() {
    final raw = rdpPortCtrl.text.trim();
    if (raw.isEmpty) return 3389;
    final v = int.tryParse(raw);
    if (v == null || v <= 0 || v > 65535) {
      log(l10n.logInvalidRdpPort(raw), isError: true);
      return 3389;
    }
    return v;
  }

  Future<int?> measureTcpPortWithRetry(
    String host,
    int port, {
    String? label,
  }) async {
    final result = await _presetSelector.measureTcpPortWithRetryDetailed(
      host,
      port,
      label: label,
    );
    return result.latency;
  }

  Future<({int? latency, String? error})> measureTcpPortWithRetryDetailed(
    String host,
    int port, {
    String? label,
  }) {
    return _presetSelector.measureTcpPortWithRetryDetailed(
      host,
      port,
      label: label,
    );
  }

  String? _diagnosticTarget() {
    final rdpHost = rdpHostCtrl.text.trim();
    if (rdpHost.isNotEmpty) {
      try {
        return InputSanitizer.sanitizeHostname(
          rdpHost,
          fieldName: l10n.rdpServer,
        );
      } on ArgumentError catch (e) {
        log(
          l10n.logInvalidConfiguration(l10n.rdpServer, '$e'),
          isError: true,
        );
        return null;
      }
    }
    final gateway = gatewayCtrl.text.trim();
    if (gateway.isNotEmpty) {
      try {
        return InputSanitizer.sanitizeIpv4(
          gateway,
          fieldName: l10n.gateway,
        );
      } on ArgumentError catch (e) {
        log(
          l10n.logInvalidConfiguration(l10n.gateway, '$e'),
          isError: true,
        );
        return null;
      }
    }
    return null;
  }

  Future<void> runDiagnostics() async {
    if (_busy) return;
    clearGuidance();
    _busy = true;
    _step = ConnectionStep.diagnostics;
    _notify();
    log(l10n.logDiagnosticsStart);

    try {
      await _saveSettingsSafely();
      try {
        final dns = await networkDiagnostics.flushDns();
        log(dns);
      } catch (e) {
        log(l10n.logDnsCacheError('$e'), isError: true);
      }
      try {
        final cache = await networkDiagnostics.clearNetworkCaches();
        log(cache);
      } catch (e) {
        log(l10n.logArpCacheError('$e'), isError: true);
      }
      final target = _diagnosticTarget();
      if (target == null) {
        log(l10n.logDiagnosticsTargetMissing, isError: true);
      } else {
        try {
          final ping = await networkDiagnostics.ping(target);
          if (ping != null) {
            log(l10n.logPingResult(target, ping));
          } else if (networkDiagnostics.lastProbeError != null) {
            log(
              l10n.logPingFailed(
                target,
                networkDiagnostics.lastProbeError!,
              ),
              isError: true,
            );
          } else {
            log(l10n.logPingUnreachable(target), isError: true);
          }
        } catch (e) {
          log(l10n.logPingFailed(target, '$e'), isError: true);
        }
      }
      log(l10n.logDiagnosticsDone);
      setGuidance(
        l10n.guidanceDiagnosticsDoneTitle,
        bullets: [
          l10n.guidanceDiagnosticsDoneBullet1,
          l10n.guidanceDiagnosticsDoneBullet2,
        ],
      );
      _step = ConnectionStep.idle;
      _notify();
    } catch (e) {
      log(l10n.logDiagnosticsFailed('$e'), isError: true);
      setErrorGuidance(e);
      _step = ConnectionStep.error;
      _notify();
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> runConnectionTroubleshooter() async {
    if (_busy) return;
    var gateway = gatewayCtrl.text.trim();
    var iface = ifaceCtrl.text.trim();
    var subnets = parseSubnets();
    final findings = <String>[];

    clearGuidance();
    _busy = true;
    _step = ConnectionStep.diagnostics;
    _notify();
    log(l10n.logTroubleshooterStart);

    try {
      await saveSettings();
      WifiConnectionInfo? wifiInfo;
      if (_isWifiSupported) {
        wifiInfo = await syncCurrentWifiInfo(silent: true);
        gateway = gatewayCtrl.text.trim();
        iface = ifaceCtrl.text.trim();

        if (wifiInfo == null || wifiInfo.ssid.trim().isEmpty) {
          log(l10n.logNoActiveWifiError, isError: true);
          findings.add(l10n.findingNoActiveWifi);
        } else {
          log(
            l10n.logCurrentWifiSummary(
              wifiInfo.ssid,
              wifiInfo.interfaceName.isEmpty
                  ? l10n.valueNotAvailable
                  : wifiInfo.interfaceName,
              wifiInfo.gateway.isEmpty
                  ? l10n.valueNotAvailable
                  : wifiInfo.gateway,
            ),
          );
        }
      }
      subnets = parseSubnets();

      if (gateway.isEmpty || iface.isEmpty) {
        try {
          final info = await routeManager.getPrimaryDefaultRouteInfo();
          gateway = gateway.isEmpty ? (info['gateway'] ?? '').trim() : gateway;
          iface = iface.isEmpty ? (info['interfaceName'] ?? '').trim() : iface;
          if (gateway.isNotEmpty) gatewayCtrl.text = gateway;
          if (iface.isNotEmpty) ifaceCtrl.text = iface;
        } catch (_) {}
      }

      String? safeGateway;
      String? safeIface;
      if (gateway.isEmpty || iface.isEmpty) {
        if (_requiresNetworkConfig) {
          log(
            l10n.logMissingGatewayInterface,
            isError: true,
          );
          findings.add(l10n.findingMissingGatewayInterface);
        }
      } else {
        try {
          safeGateway = InputSanitizer.sanitizeIpv4(
            gateway,
            fieldName: l10n.gateway,
          );
        } on ArgumentError catch (e) {
          log(
            l10n.logInvalidConfiguration(l10n.gateway, '$e'),
            isError: true,
          );
          findings.add(l10n.findingInvalidConfiguration(l10n.gateway));
        }
        try {
          safeIface = InputSanitizer.sanitizeInterfaceName(
            iface,
            fieldName: l10n.networkInterface,
          );
        } on ArgumentError catch (e) {
          log(
            l10n.logInvalidConfiguration(l10n.networkInterface, '$e'),
            isError: true,
          );
          findings.add(l10n.findingInvalidConfiguration(l10n.networkInterface));
        }
        if (safeGateway != null && safeIface != null) {
          log(l10n.logBaseConfigReady(safeGateway, safeIface));
        }
      }

      if (preferMostStableServer &&
          wifiInfo != null &&
          wifiInfo.ssid.trim().isNotEmpty) {
        await diagnoseBestServerPreset(updateGuidance: false);
      }

      List<String>? safeSubnets;
      if (subnets.isNotEmpty) {
        try {
          safeSubnets = InputSanitizer.sanitizeSubnets(
            subnets,
            fieldName: l10n.hospitalSubnets,
          );
        } on ArgumentError catch (e) {
          log(
            l10n.logInvalidConfiguration(l10n.hospitalSubnets, '$e'),
            isError: true,
          );
          findings.add(
            l10n.findingInvalidConfiguration(l10n.hospitalSubnets),
          );
        }
      }

      final rawHost = rdpHostCtrl.text.trim();
      final resolvedPort = parsePort();

      final available = await rdpLauncher.isRdpClientAvailable();
      log(
        available ? l10n.logRdpClientAvailable : l10n.logRdpClientUnavailable,
        isError: !available,
      );
      if (!available) {
        findings.add(l10n.findingRdpClientUnavailable);
      }

      if (_supportsRouteChanges &&
          safeSubnets != null &&
          safeGateway != null &&
          safeIface != null) {
        final missingRoutes = await routeManager.verifyRoutes(
          hospitalSubnets: safeSubnets,
          gateway: safeGateway,
          interfaceName: safeIface,
        );
        if (missingRoutes.isEmpty) {
          log(l10n.logRoutesPresent);
        } else {
          final routes = missingRoutes.join(', ');
          log(
            l10n.logRoutesMissing(routes),
            isError: true,
          );
          findings.add(l10n.findingRoutesMissing(routes));
        }
      }

      String? resolvedHost;
      if (rawHost.isEmpty) {
        log(l10n.logMissingRdpHost, isError: true);
        findings.add(l10n.findingMissingRdpHost);
      } else {
        try {
          resolvedHost = InputSanitizer.sanitizeHostname(
            rawHost,
            fieldName: l10n.rdpServer,
          );
        } on ArgumentError catch (e) {
          log(
            l10n.logInvalidConfiguration(l10n.rdpServer, '$e'),
            isError: true,
          );
          findings.add(l10n.findingInvalidConfiguration(l10n.rdpServer));
        }
      }

      if (resolvedHost != null) {
        final ping = await networkDiagnostics.ping(resolvedHost);
        if (ping != null) {
          log(l10n.logIcmpResult(resolvedHost, ping));
        } else if (networkDiagnostics.lastProbeError != null) {
          log(
            l10n.logPingFailed(
              resolvedHost,
              networkDiagnostics.lastProbeError!,
            ),
            isError: true,
          );
        } else {
          log(
            l10n.logIcmpUnreachable(resolvedHost),
            isError: true,
          );
        }
        final tcp = await measureTcpPortWithRetry(resolvedHost, resolvedPort);
        if (tcp != null) {
          final suggestedProfile = friendlyRdpProfile(
            selectAdaptiveRdpProfile(tcp),
          );
          log(
            l10n.logTcpOpen(
              resolvedPort,
              resolvedHost,
              tcp,
              suggestedProfile,
            ),
          );
        } else {
          final probeError = networkDiagnostics.lastProbeError;
          log(
            '${l10n.logTcpFailed(resolvedPort, resolvedHost)}'
            '${probeError == null ? '' : ' ${l10n.logCauseLabel(probeError)}'}',
            isError: true,
          );
          findings.add(l10n.findingRdpDidNotRespond(resolvedPort));
        }
      }

      log(l10n.logTroubleshooterDone);
      if (findings.isEmpty) {
        setGuidance(
          l10n.guidanceAllReadyTitle,
          bullets: [
            l10n.guidanceAllReadyBullet1,
            l10n.guidanceAllReadyBullet2,
          ],
        );
      } else {
        setGuidance(
          l10n.guidanceIssuesFoundTitle,
          bullets: findings,
          isError: true,
        );
      }
      _step = ConnectionStep.idle;
      _notify();
    } catch (e) {
      log(l10n.logTroubleshooterFailed('$e'), isError: true);
      setErrorGuidance(e);
      _step = ConnectionStep.error;
      _notify();
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> connect() async {
    if (_busy) return;
    final subnets = parseSubnets();

    if (subnets.isEmpty && _requiresNetworkConfig) {
      log(l10n.logInvalidNoSubnets, isError: true);
      return;
    }

    clearGuidance();
    _busy = true;
    _step = ConnectionStep.diagnostics;
    _notify();

    try {
      await _saveSettingsSafely();

      final hostBeforeAuto = rdpHostCtrl.text.trim();
      final hostIsPreset = serverPresets.any((p) => p.host == hostBeforeAuto);
      final shouldAutoSelect = preferMostStableServer &&
          serverPresets.isNotEmpty &&
          (hostBeforeAuto.isEmpty || hostIsPreset);

      final host = rdpHostCtrl.text.trim();
      final user = rdpUserCtrl.text.trim();
      final domain = rdpDomainCtrl.text.trim();
      final selectedWifi = resolvedWifiSsid();
      String gateway = gatewayCtrl.text.trim();
      String iface = ifaceCtrl.text.trim();
      final port = parsePort();

      if (host.isEmpty && !shouldAutoSelect) {
        log(l10n.logInvalidNoHost, isError: true);
        setGuidance(
          l10n.guidanceMissingRdpServerTitle,
          bullets: [
            l10n.guidanceMissingRdpServerBullet1,
            l10n.guidanceMissingRdpServerBullet2,
          ],
          isError: true,
        );
        return;
      }

      // Sin un SSID objetivo no hay una conexión posterior que refresque estos
      // valores, así que se usa la ruta por defecto. Con SSID, el workflow los
      // obtiene después de conectar para no reutilizar datos de otra red.
      if (_requiresNetworkConfig &&
          selectedWifi.isEmpty &&
          (gateway.isEmpty || iface.isEmpty)) {
        log(l10n.logDetectingGateway);
        try {
          final info = await routeManager.getPrimaryDefaultRouteInfo();
          gateway = gateway.isEmpty ? (info['gateway'] ?? '').trim() : gateway;
          iface = iface.isEmpty ? (info['interfaceName'] ?? '').trim() : iface;
          if (gateway.isNotEmpty) gatewayCtrl.text = gateway;
          if (iface.isNotEmpty) ifaceCtrl.text = iface;
        } catch (_) {}
      }

      final canConnectWifi = selectedWifi.isNotEmpty && wifiSupported;
      if (_requiresNetworkConfig &&
          (gateway.isEmpty || iface.isEmpty) &&
          !canConnectWifi) {
        log(l10n.logMissingGatewayInterfaceHint, isError: true);
        setGuidance(
          l10n.guidanceMissingNetworkDataTitle,
          bullets: [
            l10n.guidanceMissingNetworkDataBullet1,
            l10n.guidanceMissingNetworkDataBullet2,
            l10n.guidanceMissingNetworkDataBullet3,
          ],
          isError: true,
        );
        return;
      }

      if (_splitTunnelActive) {
        log(l10n.logClosingPreviousTunnel);
        if (_supportsRouteChanges) {
          try {
            await routeManager.disableSplitTunnel();
          } catch (e) {
            log(l10n.logCloseTunnelError('$e'), isError: true);
            setErrorGuidance(e);
            return;
          }
        }
        _splitTunnelActive = false;
        try {
          await settings?.clearPendingSplitTunnelCleanup();
        } catch (_) {}
      }

      await for (final state in workflowService.connect(
        subnets: subnets,
        host: host,
        user: user,
        domain: domain,
        selectedWifi: selectedWifi,
        gateway: gateway,
        iface: iface,
        resolvedPort: port,
        rdpProfile: rdpProfile,
        wifiPassword: wifiPasswordCtrl.text,
        onSelectServer: shouldAutoSelect
            ? () async {
                log(l10n.logSelectingBestServer);
                try {
                  final best =
                      await diagnoseBestServerPreset(updateGuidance: true);
                  if (best == null) return null;
                  return (host: best.host, port: best.port);
                } catch (e) {
                  log(
                    l10n.logSelectBestServerError('$e'),
                    isError: true,
                  );
                  return null;
                }
              }
            : null,
        onSplitTunnelEnabled: (subnets, gateway, iface) async {
          _splitTunnelActive = true;
          _notify();
          await _persistSplitTunnelCleanup(
            subnets: subnets,
            gateway: gateway,
            interfaceName: iface,
          );
        },
        onSplitTunnelUnavailable: () async {
          _splitTunnelActive = false;
          _notify();
        },
        onSplitTunnelRolledBack: () async {
          _splitTunnelActive = false;
          _notify();
          try {
            await settings?.clearPendingSplitTunnelCleanup();
          } catch (_) {
            // Si falla, el registro se reintentará en el próximo arranque.
          }
        },
      )) {
        _step = state.step;
        log(state.logMessage, isError: state.isError);

        if (state.isFinished && !state.isError) {
          await _saveSettingsSafely();
          setGuidance(
            l10n.guidanceConnectedTitle,
            bullets: [
              l10n.guidanceConnectedBullet1,
              l10n.guidanceConnectedBullet2,
            ],
          );
        } else if (state.isFinished && state.isError) {
          setErrorGuidanceType(state.errorType ?? MedLinkErrorType.unknown);
        }
        _notify();
      }
    } finally {
      wifiPasswordCtrl.clear();
      _busy = false;
      if (_step == ConnectionStep.diagnostics) {
        _step = ConnectionStep.idle;
      }
      _notify();
    }
  }

  Future<void> disconnect() async {
    if (_busy) return;
    clearGuidance();
    _busy = true;
    _notify();
    log(l10n.logDisconnecting);
    try {
      if (_supportsRouteChanges) {
        final msg = await routeManager.disableSplitTunnel();
        log(msg);
      }
      _splitTunnelActive = false;
      try {
        await settings?.clearPendingSplitTunnelCleanup();
      } catch (e) {
        log(l10n.logClearRouteRecordError('$e'), isError: true);
      }
      _notify();
      setReadyGuidance();
    } catch (e) {
      log(l10n.logDisconnectError('$e'), isError: true);
      setErrorGuidance(e);
    } finally {
      _busy = false;
      _step = ConnectionStep.idle;
      _notify();
    }
  }

  Future<void> resetSettings() async {
    if (_busy) return;
    final s = settings;
    if (s == null) return;

    _busy = true;
    _notify();
    try {
      final cleaned = await _cleanupStaleSplitTunnel();
      if (!cleaned) {
        setErrorGuidance(
          const RouteConfigurationException(
            'No se pudieron retirar las rutas de una sesión anterior.',
          ),
        );
        return;
      }
      if (_splitTunnelActive) {
        if (_supportsRouteChanges) {
          await routeManager.disableSplitTunnel();
        }
        _splitTunnelActive = false;
      }
      await s.clear();

      subnetsCtrl.text = s.hospitalSubnetsAsText;
      gatewayCtrl.text = s.gateway;
      ifaceCtrl.text = s.interfaceName;
      rdpHostCtrl.text = s.rdpHost;
      rdpPortCtrl.text = s.rdpPort.toString();
      rdpUserCtrl.text = s.rdpUsername;
      rdpDomainCtrl.text = s.rdpDomain;
      rdpProfile = s.rdpProfile;
      _preferMostStableServer = s.preferMostStableServer;
      selectedWifiSsid = s.wifiSsid.isEmpty ? null : s.wifiSsid;
      manualWifiCtrl.text = s.wifiSsid;
      _presetSelector.selectedPresetId = s.selectedServerPresetId;
      wifiPasswordCtrl.clear();
      _notify();
      log(l10n.logSettingsReset);
      refreshWifiNetworks(silent: true);
      syncCurrentWifiInfo(silent: true);
    } catch (e) {
      log(l10n.logDisconnectError('$e'), isError: true);
      setErrorGuidance(e);
    } finally {
      _busy = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    subnetsCtrl.dispose();
    gatewayCtrl.dispose();
    ifaceCtrl.dispose();
    rdpHostCtrl.dispose();
    rdpPortCtrl.dispose();
    rdpUserCtrl.dispose();
    rdpDomainCtrl.dispose();
    manualWifiCtrl.dispose();
    wifiPasswordCtrl.dispose();
    super.dispose();
  }
}
