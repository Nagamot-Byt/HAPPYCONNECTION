/// Abstract interface for managing per-app VPN profiles on mobile platforms.
///
/// On iOS and Android, split-tunneling is achieved by provisioning a VPN
/// profile that routes only hospital-bound traffic through the segregated
/// WiFi (HIS) while all other traffic remains on the device's primary
/// internet connection.
///
/// Desktop platforms (Windows, macOS, Linux) use direct routing-table
/// manipulation instead — see [RouteManager].
abstract class VpnManager {
  /// Install (or update) a per-app VPN profile for split-tunneling.
  ///
  /// Parameters:
  /// - [hospitalSubnets]: List of hospital CIDR ranges to tunnel.
  /// - [hospitalGateway]: Gateway IP for the hospital network.
  /// - [hospitalSsid]: The WiFi SSID this profile should auto-connect on.
  /// - [serverAddress]: VPN server address (unused for on-demand profiles).
  ///
  /// Returns `true` on success.
  Future<bool> installVpnProfile({
    required List<String> hospitalSubnets,
    required String hospitalGateway,
    String? hospitalSsid,
    String? serverAddress,
  });

  /// Remove the previously-installed VPN profile.
  ///
  /// Returns `true` on success, `false` if no profile was installed.
  Future<bool> removeVpnProfile();

  /// Check whether a MedLink Connect VPN profile is currently installed.
  Future<bool> isVpnProfileInstalled();
}
