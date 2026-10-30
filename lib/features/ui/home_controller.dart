import 'dart:async';
import 'package:flutter/material.dart';
import 'package:medlink_connect/core/connection_workflow_service.dart';
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

class HomeController extends ChangeNotifier {
  final SettingsStorage? settings;
  final WifiManager? wifiManager;
  final RouteManager routeManager;
  final NetworkDiagnostics networkDiagnostics;
  final RdpLauncher rdpLauncher;
  final ConnectionWorkflowService workflowService;

  HomeController({
    this.settings,
    this.wifiManager,
    required this.routeManager,
    required this.networkDiagnostics,
    required this.rdpLauncher,
    required this.workflowService,
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
  final List<String> _logs = [];
  List<String> get logs => List.unmodifiable(_logs);

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
    final time =
        DateTime.now().toIso8601String().split('T').last.substring(0, 12);
    final prefix = isError ? '❌ ' : '✅ ';
    _logs.add('[$time] $prefix$message');
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
      'Listo para conectar',
      bullets: [
        '1. Selecciona la red Wi-Fi o detecta la actual.',
        '2. Opcional: Elige un servidor o deja la selección automática.',
        '3. Pulsa "Conectar y abrir RDP".',
      ],
    );
  }

  void setErrorGuidance(Object error) {
    final eStr = error.toString().toLowerCase();
    if (eStr.contains('permiso') ||
        eStr.contains('administrador') ||
        eStr.contains('elevado')) {
      setGuidance(
        'Faltan permisos de Administrador',
        bullets: [
          'Windows requiere permisos elevados para modificar las rutas de red (túnel dividido).',
          'Cierra la aplicación y vuelve a abrirla haciendo clic derecho > "Ejecutar como administrador".',
          'Si ya está como administrador, verifica el UAC.',
        ],
        isError: true,
      );
    } else if (eStr.contains('wi-fi') ||
        eStr.contains('wifi') ||
        eStr.contains('wlan')) {
      setGuidance(
        'Problema con la red Wi-Fi',
        bullets: [
          'Verifica que el nombre de la red y la contraseña sean correctos.',
          'Para redes abiertas deja la contraseña vacía.',
          'Conéctate manualmente desde Windows y luego usa "Detectar red actual".',
        ],
        isError: true,
      );
    } else if (eStr.contains('ruta') ||
        eStr.contains('route') ||
        eStr.contains('gateway') ||
        eStr.contains('interfaz')) {
      setGuidance(
        'Problema con rutas/gateway',
        bullets: [
          'Usa "Detectar red actual" para actualizar gateway e interfaz.',
          'Asegúrate de estar conectado a la red del hospital.',
          'Verifica que las subredes hospitalarias sean correctas.',
          'Requiere permisos de Administrador para agregar rutas.',
        ],
        isError: true,
      );
    } else if (eStr.contains('rdp') ||
        eStr.contains('mstsc') ||
        eStr.contains('3389')) {
      setGuidance(
        'Problema con RDP/puerto 3389',
        bullets: [
          'Verifica que el servidor RDP sea accesible por el puerto configurado.',
          'Usa "Ayudarme a corregir" para diagnosticar rutas y conectividad.',
          'Asegúrate de tener el cliente RDP de Windows disponible.',
        ],
        isError: true,
      );
    } else {
      setGuidance(
        'La conexión no se completó',
        bullets: [
          'Revisa el registro de actividad para ver el motivo exacto.',
          'Usa "Ayudarme a corregir" para intentar reparar el problema automáticamente.',
          'Si persiste, verifica permisos de Administrador y conexión Wi-Fi.',
        ],
        isError: true,
      );
    }
  }

  Future<void> init() async {
    _logs.clear();
    log('Iniciando MedLink Connect...');
    try {
      await _loadSettings();
    } catch (e) {
      log('No se pudieron cargar los ajustes guardados: $e', isError: true);
    }
    try {
      await _cleanupStaleSplitTunnel();
    } catch (e) {
      log('No se pudieron limpiar rutas de una sesión anterior: $e',
          isError: true);
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

    log('Detectado un túnel anterior sin cierre limpio; retirando rutas…');
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
      log('Rutas de la sesión anterior eliminadas.');
    } else {
      log(
        'No se pudieron retirar todas las rutas previas: ${failures.join(', ')}',
        isError: true,
      );
    }
  }

  Future<void> _loadSettings() async {
    final s = settings;
    if (s == null) {
      log('Almacenamiento no disponible; se usarán valores en memoria.');
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

    serverPresets = const [
      ServerPreset(
          id: 'pediatrico',
          label: 'Pediatría',
          host: 'serv_pediatrico.huv.gov.co',
          port: 3389),
      ServerPreset(
          id: 'ginecologico',
          label: 'Ginecología',
          host: 'serv_ginecologico.huv.gov.co',
          port: 3389),
      ServerPreset(
          id: 'moviles',
          label: 'Móviles',
          host: 'serv_moviles.huv.gov.co',
          port: 3389),
      ServerPreset(
          id: 'consulta_externa',
          label: 'Consulta Externa',
          host: 'serv_const_ext.huv.gov.co',
          port: 3389),
      ServerPreset(
          id: 'urgencias',
          label: 'Urgencias',
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
      log('No se pudieron guardar los ajustes: $e', isError: true);
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
      log('Buscando redes Wi-Fi...');
    }
    try {
      final networks = await wifiManager!.scanNetworks();
      _wifiNetworks = networks;
      if (!silent) log('Se encontraron ${networks.length} redes Wi-Fi.');
    } catch (e) {
      if (!silent) log('Error al buscar redes Wi-Fi: $e', isError: true);
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
          log('Red actual: ${info.ssid}. Gateway: ${gatewayCtrl.text}, Interfaz: ${ifaceCtrl.text}.');
        }
      } else {
        if (!silent) log('No hay red Wi-Fi activa.');
      }
      notifyListeners();
      return info;
    } catch (e) {
      if (!silent) log('Error obteniendo red actual: $e', isError: true);
      notifyListeners();
      return null;
    }
  }

  // --- Extracted Methods ---

  String friendlyRdpProfile(String value) {
    return switch (value) {
      'stable' => 'Máxima estabilidad',
      'speed' => 'Máxima velocidad',
      _ => 'Adaptativo',
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
      log('Preset aplicado: ${preset.label} (${preset.host})');
      notifyListeners();
    }
  }

  Future<ServerPreset?> diagnoseBestServerPreset({
    bool updateGuidance = true,
  }) async {
    if (serverPresets.isEmpty) return null;
    log('Diagnosticando mejor servidor...', isError: false);
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
                log('Servidor ${preset.label} responde en ${ms}ms');
                responses.add(MapEntry(preset, ms));
              }
            } catch (e) {
              log('Servidor ${preset.label} no respondió: $e');
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
        log('Mejor servidor: ${best.label} (${bestMs}ms).');
      }
      if (updateGuidance) applyServerPreset(best, announce: false);
      return best;
    }
    final fallback = serverPresets.first;
    log(
      'Ningún servidor preconfigurado respondió. Se usará ${fallback.label} '
      'para intentar la conexión.',
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
          'Wi-Fi del hospital listo',
          bullets: [
            'La red ya quedó conectada en Windows.',
            gatewayCtrl.text.trim().isEmpty
                ? 'Gateway pendiente: usa "Detectar red actual" si no se completa.'
                : 'Gateway: ${gatewayCtrl.text.trim()}',
            ifaceCtrl.text.trim().isEmpty
                ? 'Interfaz pendiente: usa "Detectar red actual" si no se completa.'
                : 'Interfaz: ${ifaceCtrl.text.trim()}',
            'Ahora puedes pulsar "Conectar y abrir RDP".',
          ],
        );
        await saveSettings();
      } else {
        setGuidance(
          'No se completó la conexión Wi-Fi',
          bullets: [
            'Verifica que la red del hospital esté seleccionada.',
            'Confirma la contraseña e inténtalo de nuevo.',
            'Si es red abierta, deja la contraseña vacía.',
            'Si Windows tarda en responder, espera unos segundos y pulsa otra vez.',
          ],
          isError: true,
        );
      }
    } catch (e) {
      log('Error conectando Wi-Fi: $e', isError: true);
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
          log(
            'Windows ya ve la red "$ssid", esperando interfaz y gateway...',
          );
        }
        stableAttempts = 0;
        continue;
      }
      stableAttempts++;
      if (stableAttempts >= 2) {
        log('Windows confirmó la red "$ssid" con parámetros estables.');
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
        log('No hay Wi-Fi seleccionado para conectar.', isError: true);
      }
      return false;
    }
    final password = wifiPasswordCtrl.text;
    log('Conectando a Wi-Fi: $selectedWifi...');
    if (wifiManager != null) {
      final res =
          await wifiManager!.connect(ssid: selectedWifi, password: password);
      // La respuesta puede ser solo "solicitud enviada"; la fuente de verdad
      // es que el sistema reporte la SSID objetivo.
      final confirmed = await waitForTargetWifiConnection(selectedWifi);
      if (confirmed == null) {
        log(
          'El sistema no confirmó la red "$selectedWifi". '
          '${res.trim().isEmpty ? '' : 'Respuesta: $res'}',
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
      final gatewaySuffix =
          defaultGateway.isEmpty ? '' : ' (gateway $defaultGateway)';
      log(
        'Aviso: la ruta por defecto de Windows sigue saliendo por '
        '"$defaultInterface"$gatewaySuffix. Eso significa que el '
        'Internet general tambien usa esa interfaz. Para mantener '
        'Internet normal mientras HIS va por rutas especificas, '
        'necesitas otra interfaz activa para la salida a Internet.',
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
      log('Puerto RDP inválido ("$raw"). Se usará 3389.', isError: true);
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
          'Reintentando acceso TCP al servidor'
          '${label == null ? '' : ' $label'} '
          '($attempt/${delays.length - 1})...',
        );
        await Future<void>.delayed(delay);
      }
      final latency = await networkDiagnostics.checkTcpPort(host, port);
      if (latency != null) {
        best = best == null ? latency : (latency < best ? latency : best);
        if (attempt > 0) {
          log('El servidor respondió en el reintento ${attempt + 1}.');
        }
        break;
      }
    }
    return best;
  }

  Future<void> runDiagnostics() async {
    if (_busy) return;
    clearGuidance();
    _busy = true;
    _step = ConnectionStep.diagnostics;
    notifyListeners();
    log('Iniciando diagnósticos de red…');

    try {
      await _saveSettingsSafely();
      try {
        final dns = await networkDiagnostics.flushDns();
        log(dns);
      } catch (e) {
        log('No se pudo limpiar la caché DNS: $e', isError: true);
      }
      try {
        final cache = await networkDiagnostics.clearNetworkCaches();
        log(cache);
      } catch (e) {
        log('No se pudo limpiar la caché ARP: $e', isError: true);
      }
      try {
        final ping = await networkDiagnostics.ping('8.8.8.8');
        if (ping != null) {
          log('Ping a 8.8.8.8: ${ping}ms');
        } else {
          log('Ping a 8.8.8.8: inalcanzable', isError: true);
        }
      } catch (e) {
        log('Ping a 8.8.8.8 falló: $e', isError: true);
      }
      log('Diagnósticos completados.');
      setGuidance(
        'Revisión básica completada',
        bullets: [
          'El diagnóstico terminó y dejó registro en la parte inferior.',
          'Si el problema sigue, usa "Ayudarme a corregir" para revisar Wi-Fi, rutas y RDP.',
        ],
      );
      _step = ConnectionStep.idle;
      notifyListeners();
    } catch (e) {
      log('Diagnósticos fallaron: $e', isError: true);
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
    log('Iniciando solucionador de problemas de conexión…');

    try {
      await saveSettings();
      final wifiInfo = await syncCurrentWifiInfo(silent: true);
      if (wifiInfo == null || wifiInfo.ssid.trim().isEmpty) {
        log('No se detecta una red Wi-Fi activa.', isError: true);
        findings.add('No hay una red Wi-Fi activa detectada en Windows.');
      } else {
        log(
          'Wi-Fi actual: ${wifiInfo.ssid} | Interfaz: ${wifiInfo.interfaceName.isEmpty ? 'sin dato' : wifiInfo.interfaceName} | Gateway: ${wifiInfo.gateway.isEmpty ? 'sin dato' : wifiInfo.gateway}.',
        );
      }

      if (gateway.isEmpty || iface.isEmpty) {
        log(
          'Faltan gateway o interfaz en la configuración avanzada.',
          isError: true,
        );
        findings.add(
          'Falta completar gateway o interfaz en las opciones avanzadas.',
        );
      } else {
        log('Configuración base lista: gateway $gateway, interfaz $iface.');
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
        available
            ? 'Cliente RDP disponible.'
            : 'No se encontró un cliente RDP disponible.',
        isError: !available,
      );
      if (!available) {
        findings.add('Windows no reporta un cliente RDP disponible.');
      }

      if (subnets.isNotEmpty && gateway.isNotEmpty && iface.isNotEmpty) {
        final missingRoutes = await routeManager.verifyRoutes(
          hospitalSubnets: subnets,
          gateway: gateway,
          interfaceName: iface,
        );
        if (missingRoutes.isEmpty) {
          log('Las rutas del hospital ya están presentes.');
        } else {
          log(
            'Faltan rutas del hospital: ${missingRoutes.join(', ')}.',
            isError: true,
          );
          findings.add(
            'Aún faltan rutas del hospital: ${missingRoutes.join(', ')}.',
          );
        }
      }

      if (resolvedHost.isEmpty) {
        log('Falta el host RDP para completar la prueba.', isError: true);
        findings.add('Falta escribir el host o IP del servidor RDP.');
      } else {
        final ping = await networkDiagnostics.ping(resolvedHost);
        if (ping != null) {
          log('ICMP hacia $resolvedHost: ${ping}ms.');
        } else {
          log(
            'El host $resolvedHost no respondió a ICMP. Puede ser normal si el servidor bloquea ping.',
            isError: true,
          );
        }
        final tcp = await measureTcpPortWithRetry(resolvedHost, resolvedPort);
        if (tcp != null) {
          final suggestedProfile = friendlyRdpProfile(
            selectAdaptiveRdpProfile(tcp),
          );
          log(
            'TCP $resolvedPort abierto en $resolvedHost (${tcp}ms). Perfil recomendado: $suggestedProfile.',
          );
        } else {
          log(
            'No se pudo abrir TCP $resolvedPort en $resolvedHost. Revisa rutas, firewall o disponibilidad del servidor.',
            isError: true,
          );
          findings
              .add('El servidor RDP no respondió por el puerto $resolvedPort.');
        }
      }

      log('Solucionador completado.');
      if (findings.isEmpty) {
        setGuidance(
          'Todo parece listo para conectar',
          bullets: [
            'Wi-Fi, rutas y cliente RDP se ven correctos.',
            'Ya puedes pulsar "Conectar y abrir RDP".',
          ],
        );
      } else {
        setGuidance(
          'Encontré puntos para corregir',
          bullets: findings,
          isError: true,
        );
      }
      _step = ConnectionStep.idle;
      notifyListeners();
    } catch (e) {
      log('Solucionador falló: $e', isError: true);
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
      log(
        'Configuración inválida: agrega al menos una subred del hospital.',
        isError: true,
      );
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
        log('Configuración inválida: host RDP es obligatorio.', isError: true);
        setGuidance(
          'Falta el servidor RDP',
          bullets: [
            'Escribe el host o la IP del servidor.',
            'También puedes elegir un servidor preconfigurado.',
          ],
          isError: true,
        );
        return;
      }

      // Intentar detectar gateway/interfaz si faltan
      if (gateway.isEmpty || iface.isEmpty) {
        log('Detectando gateway/interfaz...');
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
        log(
          'Faltan gateway o interfaz. Usa "Detectar red actual" o completa los campos en Opciones avanzadas.',
          isError: true,
        );
        setGuidance(
          'Faltan datos de red',
          bullets: [
            'No se detectó gateway o interfaz automáticamente.',
            'Pulsa "Detectar red actual" o complétalos manualmente.',
            'Asegúrate de estar conectado a la red del hospital.',
          ],
          isError: true,
        );
        return;
      }

      if (_splitTunnelActive) {
        log('Cerrando el túnel anterior antes de reconectar…');
        try {
          await routeManager.disableSplitTunnel();
          _splitTunnelActive = false;
          try {
            await settings?.clearPendingSplitTunnelCleanup();
          } catch (_) {}
        } catch (e) {
          log('No se pudo cerrar el túnel anterior: $e', isError: true);
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
                log('Seleccionando automáticamente el servidor más estable…');
                try {
                  final best =
                      await diagnoseBestServerPreset(updateGuidance: true);
                  if (best == null) return null;
                  return (host: best.host, port: best.port);
                } catch (e) {
                  log(
                    'No se pudo seleccionar el mejor servidor: $e',
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
            'La conexión quedó iniciada',
            bullets: [
              'Si la ventana de Escritorio remoto aparece, continúa el ingreso normalmente.',
              'Si necesitas cerrar la conexión técnica, pulsa "Desconectar túnel".',
            ],
          );
        } else if (state.isFinished && state.isError) {
          setErrorGuidance(state.logMessage);
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
    log('Desconectando: deshabilitando túnel dividido…');
    try {
      final msg = await routeManager.disableSplitTunnel();
      log(msg);
      _splitTunnelActive = false;
      try {
        await settings?.clearPendingSplitTunnelCleanup();
      } catch (e) {
        log('No se pudo limpiar el registro de rutas: $e', isError: true);
      }
      notifyListeners();
      setReadyGuidance();
    } catch (e) {
      log('Error al desconectar: $e', isError: true);
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
    log('Ajustes restablecidos a predeterminados.');
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
