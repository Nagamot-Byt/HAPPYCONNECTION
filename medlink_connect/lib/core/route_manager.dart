/// Abstract interface for managing network routes.
///
/// On desktop platforms (Windows, macOS, Linux) this manipulates the
/// system routing table directly.  On mobile (iOS, Android) we configure
/// a per-app VPN / split-tunnel profile so only hospital-bound traffic
/// travels through the segregated WiFi while all other traffic remains on
/// the device's primary internet connection.
abstract class RouteManager {
  /// Add a static route so traffic destined for [destinationCidr] is
  /// routed through [gateway] on interface [interfaceName].
  ///
  /// Returns `true` on success.
  Future<bool> addRoute({
    required String destinationCidr,
    required String gateway,
    required String interfaceName,
  });

  /// Remove a previously-added route.
  Future<bool> removeRoute({
    required String destinationCidr,
  });

  /// Enable split-tunneling for the hospital network.
  ///
  /// On mobile this provisions a VPN profile; on desktop this sets up
  /// policy-based routing rules.
  Future<bool> enableSplitTunnel({
    required List<String> hospitalSubnets,
    required String hospitalGateway,
    required String hospitalInterface,
  });

  /// Disable split-tunneling and restore normal routing.
  Future<bool> disableSplitTunnel();
}
