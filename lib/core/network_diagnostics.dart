/// Abstract interface for network diagnostic operations.
///
/// Platform implementations use method channels
/// (`com.medlinkconnect/network_diagnostics`) to invoke native code.
abstract class NetworkDiagnostics {
  /// Human-readable cause of the last [ping] or [checkTcpPort] probe failure.
  ///
  /// Returns `null` after a successful probe or when no probe has run yet.
  /// Timeouts and platform errors are recorded so the UI can show the cause.
  String? get lastProbeError;

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
  /// The default implementation uses a single short probe so it can be
  /// reused in the connection flow without adding long waits.
  Future<int?> ping(String host);

  /// Tries to open a TCP connection to [host]:[port] and returns the
  /// connection time in milliseconds, or `null` when the socket can't
  /// be established within the timeout budget.
  Future<int?> checkTcpPort(String host, int port);
}
