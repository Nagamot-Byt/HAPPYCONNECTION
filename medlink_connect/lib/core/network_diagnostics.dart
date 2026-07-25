/// Abstract interface for network diagnostic operations.
///
/// Platform implementations use method channels
/// (`com.medlinkconnect/network_diagnostics`) to invoke native code.
abstract class NetworkDiagnostics {
  /// Flushes the DNS resolver cache.
  ///
  /// Returns a message describing the result. On Linux this runs
  /// `resolvectl flush-caches` with appropriate fallbacks.
  Future<String> flushDns();

  /// Clears all local network caches (ARP, neighbour tables, etc.).
  ///
  /// May require administrator / root privileges.
  Future<String> clearNetworkCaches();

  /// Pings [host] and returns the average round-trip time in milliseconds,
  /// or `null` if the host is unreachable.
  ///
  /// The default implementation pings 4 times with a 2-second timeout
  /// per probe (matching `ping -c 4 -W 2`).
  Future<int?> ping(String host);
}
