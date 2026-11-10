import 'package:flutter/foundation.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:medlink_connect/core/wifi_manager.dart';

typedef WifiFormValues = ({String gateway, String iface});

/// Estado y operaciones Wi-Fi de la pantalla principal: escaneo de SSIDs,
/// lectura de la conexión actual, confirmación de un SSID objetivo y
/// resolución de la selección frente a la entrada manual.
class WifiConnectionCoordinator {
  WifiConnectionCoordinator({
    required this.wifiManager,
    required this.l10n,
    required this.onLog,
    required this.onChanged,
    required this.currentGatewayAndInterface,
    required this.applyGatewayAndInterface,
  });

  static const String manualWifiOption = '__manual__';

  final WifiManager? wifiManager;
  final AppLocalizations l10n;
  final void Function(String message, {bool isError}) onLog;
  final VoidCallback onChanged;
  final WifiFormValues Function() currentGatewayAndInterface;
  final void Function(String gateway, String interfaceName)
      applyGatewayAndInterface;

  List<String> _networks = [];
  List<String> get networks => List.unmodifiable(_networks);

  bool _networksLoading = false;
  bool get networksLoading => _networksLoading;

  String? _scanError;
  String? get scanError => _scanError;

  String? selectedSsid;

  String _currentSsid = '';
  String get currentSsid => _currentSsid;

  bool get _isWifiSupported =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;

  bool get isSupported => _isWifiSupported && wifiManager != null;

  String resolveSsid(String manualSsid) {
    final selected = selectedSsid;
    if (selected == null ||
        selected.isEmpty ||
        selected == manualWifiOption ||
        _networks.isEmpty) {
      return manualSsid;
    }
    return selected;
  }

  bool selectManual() {
    if (selectedSsid == manualWifiOption) return false;
    selectedSsid = manualWifiOption;
    return true;
  }

  Future<void> refreshNetworks({bool silent = false}) async {
    if (wifiManager == null || !_isWifiSupported) return;
    if (!silent) {
      _networksLoading = true;
      onChanged();
      onLog(l10n.logSearchingWifi);
    }
    try {
      final networks = await wifiManager!.scanNetworks();
      final unique = networks.toSet().toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      _networks = unique;
      _scanError = null;
      if (!silent) onLog(l10n.logNetworksFound(unique.length));
    } catch (e) {
      // Un escaneo fallido deja el estado de las redes en desconocido: no se
      // muestran SSIDs posiblemente obsoletos de un escaneo anterior.
      _networks = [];
      _scanError = '$e';
      onLog(l10n.logScanWifiError('$e'), isError: true);
    } finally {
      _networksLoading = false;
      onChanged();
    }
  }

  Future<WifiConnectionInfo?> syncCurrentInfo({
    bool silent = false,
    bool overwrite = true,
  }) async {
    if (wifiManager == null || !_isWifiSupported) return null;
    try {
      final info = await wifiManager!.getCurrentConnectionInfo();
      _currentSsid = info.ssid;
      if (info.ssid.isNotEmpty) {
        if (overwrite) {
          applyGatewayAndInterface(
            info.gateway.trim(),
            info.interfaceName.trim(),
          );
        }
        final form = currentGatewayAndInterface();
        if (!silent) {
          onLog(l10n.logCurrentNetwork(info.ssid, form.gateway, form.iface));
        }
      } else {
        if (!silent) onLog(l10n.logNoActiveWifi);
      }
      onChanged();
      return info;
    } catch (e) {
      if (!silent) onLog(l10n.logCurrentNetworkError('$e'), isError: true);
      onChanged();
      return null;
    }
  }

  Future<WifiConnectionInfo?> waitForTargetConnection(String ssid) async {
    const maxAttempts = 12;
    WifiConnectionInfo? lastMatch;
    var stableAttempts = 0;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      await Future<void>.delayed(
        Duration(milliseconds: attempt == 0 ? 900 : 1400),
      );
      final info = await syncCurrentInfo(silent: true);
      if (info == null) continue;
      if (info.ssid != ssid) {
        stableAttempts = 0;
        continue;
      }
      lastMatch = info;
      final hasInterface = info.interfaceName.trim().isNotEmpty;
      final hasGateway = info.gateway.trim().isNotEmpty;
      if (!hasInterface || !hasGateway) {
        if (attempt == 0 || attempt == 3 || attempt == 6 || attempt == 9) {
          onLog(l10n.logWaitingForWifiDetails(ssid));
        }
        stableAttempts = 0;
        continue;
      }
      stableAttempts++;
      if (stableAttempts >= 2) {
        onLog(l10n.logWifiConfirmed(ssid));
        return info;
      }
    }
    if (lastMatch != null && lastMatch.ssid == ssid) {
      return lastMatch;
    }
    return null;
  }
}
