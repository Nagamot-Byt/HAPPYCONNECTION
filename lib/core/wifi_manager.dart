/// Current Wi-Fi connection details exposed by the platform layer.
class WifiConnectionInfo {
  const WifiConnectionInfo({
    required this.ssid,
    required this.interfaceName,
    required this.gateway,
  });

  final String ssid;
  final String interfaceName;
  final String gateway;

  bool get isConnected => ssid.isNotEmpty;
}

/// Abstract interface for scanning and connecting to Wi-Fi networks.
///
/// Platform implementations use method channels
/// (`com.medlinkconnect/wifi_manager`) to invoke native code.
abstract class WifiManager {
  /// Returns the visible Wi-Fi SSIDs.
  Future<List<String>> scanNetworks();

  /// Connects to [ssid]. When [password] is provided, the platform may create
  /// a temporary profile for WPA/WPA2 personal networks.
  Future<String> connect({
    required String ssid,
    String? password,
  });

  /// Returns the current Wi-Fi connection data when available.
  Future<WifiConnectionInfo> getCurrentConnectionInfo();
}
