import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:medlink_connect/core/connection_workflow_service.dart';
import 'package:medlink_connect/core/exceptions.dart';
import 'package:medlink_connect/core/network_diagnostics.dart';
import 'package:medlink_connect/core/rdp_launcher.dart';
import 'package:medlink_connect/core/route_manager.dart';
import 'package:medlink_connect/core/settings_storage.dart';
import 'package:medlink_connect/core/wifi_manager.dart';

enum ConnectionStep {
  idle,
  diagnostics,
  splitTunnel,
  preLaunch,
  launchRdp,
  done,
  error,
}

class ServerPreset {
  final String id;
  final String label;
  final String host;
  final int port;

  const ServerPreset({
    required this.id,
    required this.label,
    required this.host,
    required this.port,
  });

  bool get isConfigured => host.isNotEmpty && host != 'pendiente';
}

class ConnectionLogEntry {
  final DateTime timestamp;
  final String message;
  final bool isError;

  const ConnectionLogEntry({
    required this.timestamp,
    required this.message,
    required this.isError,
  });

  String get time =>
      timestamp.toIso8601String().split('T').last.substring(0, 12);

  String get formatted => '[$time] $message';
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
  });

  bool _loaded = false;
  bool get loaded => _loaded;

  bool _busy = false;
  bool get busy => _busy;

  ConnectionStep _step = ConnectionStep.idle;
  ConnectionStep get step => _step;

  bool _splitTunnelActive = false;
  bool get splitTunnelActive => _splitTunnelActive;

  static const int _maxLogEntries = 500;
  final List<ConnectionLogEntry> _logs = [];
  List<ConnectionLogEntry> get logEntries => List.unmodifiable(_logs);
  List<String> get logs =>
      List.unmodifiable(_logs.map((entry) => entry.formatted));

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
    notifyListeners();
  }

  bool _preferMostStableServer = true;
  bool get preferMostStableServer => _preferMostStableServer;
  set preferMostStableServer(bool value) {
    _preferMostStableServer = value;
    notifyListeners();
  }

  String _selectedServerPresetId = 'manual';
  String get selectedServerPresetId => _selectedServerPresetId;
  set selectedServerPresetId(String value) {
    _selectedServerPresetId = value;
    notifyListeners();
  }

  List<ServerPreset> _serverPresets = [];
  List<ServerPreset> get serverPresets => List.unmodifiable(_serverPresets);
  set serverPresets(List<ServerPreset> value) {
    _serverPresets = List.from(value);
    notifyListeners();
  }

  List<String> _wifiNetworks = [];
  List<String> get wifiNetworks => List.unmodifiable(_wifiNetworks);

  bool _wifiNetworksLoading = false;
  bool get wifiNetworksLoading => _wifiNetworksLoading;

  String? _selectedWifiSsid;
  String? get selectedWifiSsid => _selectedWifiSsid;
  set selectedWifiSsid(String? value) {
    _selectedWifiSsid = value;
    notifyListeners();
  }

  String _currentWifiSsid = '';
  String get currentWifiSsid => _currentWifiSsid;

  static const _kManualWifiOption = '__manual__';
  String get manualWifiOption => _kManualWifiOption;

  void log(String message, {bool isError = false}) {
    _logs.add(ConnectionLogEntry(
      timestamp: DateTime.now(),
      message: message,
      isError: isError,
    ));
    if (_logs.length > _maxLogEntries) {
      _logs.removeRange(0, _logs.length - _maxLogEntries);
    }
    notifyListeners();
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  void setGuidance(String title,
      {List<String> bullets = const [], bool isError = false}) {
    _guidanceTitle = title;
    _guidanceBullets = bullets;
    _guidanceIsError = isError;
    notifyListeners();
  }

  void clearGuidance() {
    _guidanceTitle = null;
    _guidanceBullets = [];
    _guidanceIsError = false;
    notifyListeners();
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

  MedLinkErrorType _classifyError(Object error) {
    if (error is MedLinkException) return error.type;
    if (error is ArgumentError) return MedLinkErrorType.validation;
    if (error is PlatformException) {
      final code = error.code.toLowerCase();
      if (code.contains('permiso') ||
          code.contains('privilege') ||
          code.contains('access_denied')) {
        return MedLinkErrorType.permission;
      }
      if (code.startsWith('wifi')) return MedLinkErrorType.wifi;
      if (code.startsWith('rdp')) return MedLinkErrorType.rdp;
      if (code.startsWith('route') || code.startsWith('arp')) {
        return MedLinkErrorType.route;
      }
      if (code.startsWith('flushdns') || code.startsWith('network')) {
        return MedLinkErrorType.network;
      }
    }
    return MedLinkErrorType.unknown;
  }

  void setErrorGuidance(Object error) {
    setErrorGuidanceType(_classifyError(error));
  }

  void setErrorGuidanceType(MedLinkErrorType type) {
    switch (type) {
      case MedLinkErrorType.permission:
        setGuidance(
          l10n.guidanceAdminErrorTitle,
          bullets: [
            l10n.guidanceAdminErrorBullet1,
            l10n.guidanceAdminErrorBullet2,
            l10n.guidanceAdminErrorBullet3,
          ],
          isError: true,
        );
        break;
      case MedLinkErrorType.wifi:
        setGuidance(
          l10n.guidanceWifiErrorTitle,
          bullets: [
            l10n.guidanceWifiErrorBullet1,
            l10n.guidanceWifiErrorBullet3,
            l10n.guidanceWifiErrorBullet2,
          ],
          isError: true,
        );
        break;
      case MedLinkErrorType.route:
        setGuidance(
          l10n.guidanceRouteErrorTitle,
          bullets: [
            l10n.guidanceRouteErrorBullet1,
            l10n.guidanceRouteErrorBullet2,
            l10n.guidanceRouteErrorBullet3,
            l10n.guidanceRouteErrorBullet4,
          ],
          isError: true,
        );
        break;
      case MedLinkErrorType.rdp:
        setGuidance(
          l10n.guidanceRdpErrorTitle,
          bullets: [
            l10n.guidanceRdpErrorBullet1,
            l10n.guidanceRdpErrorBullet2,
            l10n.guidanceRdpErrorBullet3,
          ],
          isError: true,
        );
        break;
      case MedLinkErrorType.network:
      case MedLinkErrorType.validation:
      case MedLinkErrorType.unknown:
        setGuidance(
          l10n.guidanceGenericErrorTitle,
          bullets: [
            l10n.guidanceGenericErrorBullet1,
            l10n.guidanceGenericErrorBullet2,
            l10n.guidanceGenericErrorBullet3,
          ],
          isError: true,
        );
    }
  }

  Future<void> init() async {
    _logs.clear();
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
    notifyListeners();
    setReadyGuidance();

    // We can run these without awaiting init
    refreshWifiNetworks(silent: true);
    syncCurrentWifiInfo(silent: true);
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

  Future<void> _cleanupStaleSplitTunnel() async {
    final s = settings;
    if (s == null) return;
    final pending = s.pendingSplitTunnelCleanup;
    if (pending == null) return;

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
    } else {
      log(
        l10n.logStaleRoutesFailed(failures.join(', ')),
        isError: true,
      );
    }
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
    _selectedServerPresetId = s.selectedServerPresetId;

    serverPresets = [
      ServerPreset(
          id: 'pediatrico',
          label: l10n.presetPediatric,
          host: 'serv_pediatrico.huv.gov.co',
          port: 3389),
      ServerPreset(
          id: 'ginecologico',
          label: l10n.presetGynecology,
          host: 'serv_ginecologico.huv.gov.co',
          port: 3389),
      ServerPreset(
          id: 'moviles',
          label: l10n.presetMobile,
          host: 'serv_moviles.huv.gov.co',
          port: 3389),
      ServerPreset(
          id: 'consulta_externa',
          label: l10n.presetOutpatient,
          host: 'serv_const_ext.huv.gov.co',
          port: 3389),
      ServerPreset(
          id: 'urgencias',
          label: l10n.presetEmergency,
          host: 'serv_urgencias.huv.gov.co',
          port: 3389),
    ];
    if (_selectedServerPresetId != 'manual' &&
        !_serverPresets.any((p) => p.id == _selectedServerPresetId)) {
      _selectedServerPresetId = 'manual';
    }
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

    final w = resolvedWifiSsid();
    if (w.isNotEmpty) {
      s.wifiSsid = w;
    }
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

  String resolvedWifiSsid() {
    if (selectedWifiSsid == _kManualWifiOption) {
      return manualWifiCtrl.text.trim();
    }
    return selectedWifiSsid ?? '';
  }

  Future<void> refreshWifiNetworks({bool silent = false}) async {
    if (wifiManager == null) return;
    if (!silent) {
      _wifiNetworksLoading = true;
      notifyListeners();
      log(l10n.logSearchingWifi);
    }
    try {
      final networks = await wifiManager!.scanNetworks();
      _wifiNetworks = networks;
      if (!silent) log(l10n.logNetworksFound(networks.length));
    } catch (e) {
      if (!silent) log(l10n.logScanWifiError('$e'), isError: true);
    } finally {
      _wifiNetworksLoading = false;
      notifyListeners();
    }
  }

  Future<WifiConnectionInfo?> syncCurrentWifiInfo({bool silent = false}) async {
    if (wifiManager == null) return null;
    try {
      final info = await wifiManager!.getCurrentConnectionInfo();
      _currentWifiSsid = info.ssid;
      if (info.ssid.isNotEmpty) {
        if (info.gateway.trim().isNotEmpty) {
          gatewayCtrl.text = info.gateway;
        }
        if (info.interfaceName.trim().isNotEmpty) {
          ifaceCtrl.text = info.interfaceName;
        }
        if (!silent) {
          log(l10n.logCurrentNetwork(
            info.ssid,
            gatewayCtrl.text,
            ifaceCtrl.text,
          ));
        }
      } else {
        if (!silent) log(l10n.logNoActiveWifi);
      }
      notifyListeners();
      return info;
    } catch (e) {
      if (!silent) log(l10n.logCurrentNetworkError('$e'), isError: true);
      notifyListeners();
      return null;
    }
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

  ServerPreset? presetById(String id) {
    for (final preset in serverPresets) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  void applyServerPreset(ServerPreset preset, {bool announce = true}) {
    rdpHostCtrl.text = preset.host;
    rdpPortCtrl.text = preset.port.toString();
    selectedServerPresetId = preset.id;
    if (announce) {
      log(l10n.logPresetApplied(preset.label, preset.host));
      notifyListeners();
    }
  }

  Future<ServerPreset?> diagnoseBestServerPreset({
    bool updateGuidance = true,
  }) async {
    if (serverPresets.isEmpty) return null;
    log(l10n.logDiagnosingBestServer, isError: false);
    final responses = <MapEntry<ServerPreset, int>>[];
    // Los cinco destinos se prueban en paralelo para no encadenar sus tiempos
    // de espera; se conserva el de menor latencia TCP.
    await Future.wait([
      for (final preset in serverPresets)
        if (preset.isConfigured)
          () async {
            try {
              final ms = await measureTcpPortWithRetry(
                preset.host,
                preset.port,
                label: preset.label,
              );
              if (ms != null && ms > 0) {
                log(l10n.logServerResponded(preset.label, ms));
                responses.add(MapEntry(preset, ms));
              }
            } catch (e) {
              log(l10n.logServerNoResponse(preset.label, '$e'));
            }
          }(),
    ]);

    ServerPreset? best;
    int? bestMs;
    for (final response in responses) {
      if (bestMs == null || response.value < bestMs) {
        best = response.key;
        bestMs = response.value;
      }
    }
    if (best != null) {
      if (bestMs != null) {
        log(l10n.logBestServer(best.label, bestMs));
      }
      if (updateGuidance) applyServerPreset(best, announce: false);
      return best;
    }
    final fallback = serverPresets.first;
    log(
      l10n.logNoServerResponded(fallback.label),
      isError: true,
    );
    if (updateGuidance) applyServerPreset(fallback, announce: false);
    return fallback;
  }

  Future<void> connectWifiOnly() async {
    if (_busy) return;
    clearGuidance();
    _busy = true;
    notifyListeners();
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
      notifyListeners();
    }
  }

  Future<WifiConnectionInfo?> waitForTargetWifiConnection(String ssid) async {
    const maxAttempts = 12;
    WifiConnectionInfo? lastMatch;
    var stableAttempts = 0;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      await Future<void>.delayed(
        Duration(milliseconds: attempt == 0 ? 900 : 1400),
      );
      final info = await syncCurrentWifiInfo(silent: true);
      if (info == null) continue;
      if (info.ssid.trim() != ssid) {
        stableAttempts = 0;
        continue;
      }
      lastMatch = info;
      final hasInterface = info.interfaceName.trim().isNotEmpty;
      final hasGateway = info.gateway.trim().isNotEmpty;
      if (!hasInterface || !hasGateway) {
        if (attempt == 0 || attempt == 3 || attempt == 6 || attempt == 9) {
          log(l10n.logWaitingForWifiDetails(ssid));
        }
        stableAttempts = 0;
        continue;
      }
      stableAttempts++;
      if (stableAttempts >= 2) {
        log(l10n.logWifiConfirmed(ssid));
        return info;
      }
    }
    if (lastMatch != null && lastMatch.ssid.trim() == ssid) {
      return lastMatch;
    }
    return null;
  }

  Future<bool> connectSelectedWifi({required bool requireSelection}) async {
    final selectedWifi = resolvedWifiSsid();
    if (selectedWifi.isEmpty) {
      if (requireSelection) {
        log(l10n.logNoWifiSelected, isError: true);
      }
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
    const delays = <Duration>[
      Duration.zero,
      Duration(milliseconds: 350),
      Duration(milliseconds: 700),
    ];

    int? best;
    for (var attempt = 0; attempt < delays.length; attempt++) {
      final delay = delays[attempt];
      if (delay > Duration.zero) {
        log(
          label == null
              ? l10n.logRetryingTcpNoLabel(attempt, delays.length - 1)
              : l10n.logRetryingTcp(label, attempt, delays.length - 1),
        );
        await Future<void>.delayed(delay);
      }
      final latency = await networkDiagnostics.checkTcpPort(host, port);
      if (latency != null) {
        best = best == null ? latency : (latency < best ? latency : best);
        if (attempt > 0) {
          log(l10n.logServerRetrySuccess(attempt + 1));
        }
        break;
      }
    }
    return best;
  }

  String? _diagnosticTarget() {
    final rdpHost = rdpHostCtrl.text.trim();
    if (rdpHost.isNotEmpty) return rdpHost;
    final gateway = gatewayCtrl.text.trim();
    if (gateway.isNotEmpty) return gateway;
    return null;
  }

  Future<void> runDiagnostics() async {
    if (_busy) return;
    clearGuidance();
    _busy = true;
    _step = ConnectionStep.diagnostics;
    notifyListeners();
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
      notifyListeners();
    } catch (e) {
      log(l10n.logDiagnosticsFailed('$e'), isError: true);
      setErrorGuidance(e);
      _step = ConnectionStep.error;
      notifyListeners();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> runConnectionTroubleshooter() async {
    if (_busy) return;
    final gateway = gatewayCtrl.text.trim();
    final iface = ifaceCtrl.text.trim();
    final subnets = parseSubnets();
    final findings = <String>[];

    clearGuidance();
    _busy = true;
    _step = ConnectionStep.diagnostics;
    notifyListeners();
    log(l10n.logTroubleshooterStart);

    try {
      await saveSettings();
      final wifiInfo = await syncCurrentWifiInfo(silent: true);
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

      if (gateway.isEmpty || iface.isEmpty) {
        log(
          l10n.logMissingGatewayInterface,
          isError: true,
        );
        findings.add(l10n.findingMissingGatewayInterface);
      } else {
        log(l10n.logBaseConfigReady(gateway, iface));
      }

      if (preferMostStableServer &&
          wifiInfo != null &&
          wifiInfo.ssid.trim().isNotEmpty) {
        await diagnoseBestServerPreset(updateGuidance: false);
      }

      final resolvedHost = rdpHostCtrl.text.trim();
      final resolvedPort = parsePort();

      final available = await rdpLauncher.isRdpClientAvailable();
      log(
        available ? l10n.logRdpClientAvailable : l10n.logRdpClientUnavailable,
        isError: !available,
      );
      if (!available) {
        findings.add(l10n.findingRdpClientUnavailable);
      }

      if (subnets.isNotEmpty && gateway.isNotEmpty && iface.isNotEmpty) {
        final missingRoutes = await routeManager.verifyRoutes(
          hospitalSubnets: subnets,
          gateway: gateway,
          interfaceName: iface,
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

      if (resolvedHost.isEmpty) {
        log(l10n.logMissingRdpHost, isError: true);
        findings.add(l10n.findingMissingRdpHost);
      } else {
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
          if (probeError != null) {
            log(
              l10n.logPingFailed(resolvedHost, probeError),
              isError: true,
            );
          }
          log(
            l10n.logTcpFailed(resolvedPort, resolvedHost),
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
      notifyListeners();
    } catch (e) {
      log(l10n.logTroubleshooterFailed('$e'), isError: true);
      setErrorGuidance(e);
      _step = ConnectionStep.error;
      notifyListeners();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> connect() async {
    if (_busy) return;
    final subnets = parseSubnets();

    if (subnets.isEmpty) {
      log(l10n.logInvalidNoSubnets, isError: true);
      return;
    }

    clearGuidance();
    _busy = true;
    _step = ConnectionStep.diagnostics;
    notifyListeners();

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

      if (host.isEmpty) {
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

      // Intentar detectar gateway/interfaz si faltan
      if (gateway.isEmpty || iface.isEmpty) {
        log(l10n.logDetectingGateway);
        try {
          await syncCurrentWifiInfo(silent: true);
        } catch (_) {}
        gateway = gatewayCtrl.text.trim();
        iface = ifaceCtrl.text.trim();
        if (gateway.isEmpty || iface.isEmpty) {
          try {
            final info = await routeManager.getPrimaryDefaultRouteInfo();
            gateway =
                gateway.isEmpty ? (info['gateway'] ?? '').trim() : gateway;
            iface =
                iface.isEmpty ? (info['interfaceName'] ?? '').trim() : iface;
            if (gateway.isNotEmpty) gatewayCtrl.text = gateway;
            if (iface.isNotEmpty) ifaceCtrl.text = iface;
          } catch (_) {}
        }
      }

      if (gateway.isEmpty || iface.isEmpty) {
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
        try {
          await routeManager.disableSplitTunnel();
          _splitTunnelActive = false;
          try {
            await settings?.clearPendingSplitTunnelCleanup();
          } catch (_) {}
        } catch (e) {
          log(l10n.logCloseTunnelError('$e'), isError: true);
          setErrorGuidance(e);
          return;
        }
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
          notifyListeners();
          await _persistSplitTunnelCleanup(
            subnets: subnets,
            gateway: gateway,
            interfaceName: iface,
          );
        },
        onSplitTunnelUnavailable: () async {
          _splitTunnelActive = false;
          notifyListeners();
        },
        onSplitTunnelRolledBack: () async {
          _splitTunnelActive = false;
          notifyListeners();
          try {
            await settings?.clearPendingSplitTunnelCleanup();
          } catch (_) {
            // Si falla, el registro se reintentará en el próximo arranque.
          }
        },
      )) {
        _step = state.step;
        if (state.step == ConnectionStep.error) {
          _splitTunnelActive = false;
        }
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
        notifyListeners();
      }
    } finally {
      wifiPasswordCtrl.clear();
      _busy = false;
      if (_step == ConnectionStep.diagnostics) {
        _step = ConnectionStep.idle;
      }
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    if (_busy) return;
    clearGuidance();
    _busy = true;
    notifyListeners();
    log(l10n.logDisconnecting);
    try {
      final msg = await routeManager.disableSplitTunnel();
      log(msg);
      _splitTunnelActive = false;
      try {
        await settings?.clearPendingSplitTunnelCleanup();
      } catch (e) {
        log(l10n.logClearRouteRecordError('$e'), isError: true);
      }
      notifyListeners();
      setReadyGuidance();
    } catch (e) {
      log(l10n.logDisconnectError('$e'), isError: true);
      setErrorGuidance(e);
    } finally {
      _busy = false;
      _step = ConnectionStep.idle;
      notifyListeners();
    }
  }

  Future<void> resetSettings() async {
    final s = settings;
    if (s == null) return;
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
    _selectedServerPresetId = s.selectedServerPresetId;
    wifiPasswordCtrl.clear();
    notifyListeners();
    log(l10n.logSettingsReset);
    refreshWifiNetworks(silent: true);
    syncCurrentWifiInfo(silent: true);
  }

  @override
  void dispose() {
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
