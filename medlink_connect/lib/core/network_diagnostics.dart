/// Abstract interface for OS-level network diagnostics.
///
/// Each platform provides its own implementation via a platform channel.
/// This interface exposes the operations the UI layer needs — never the
/// underlying shell commands or platform APIs directly.
abstract class NetworkDiagnostics {
  /// Flush the DNS cache on the current platform.
  ///
  /// Returns `true` if the flush succeeded (or was a no-op), `false` on error.
  Future<bool> flushDns();

  /// Clear system network caches (ARP, routing table cache, etc.).
  Future<bool> clearNetworkCaches();

  /// Ping [host] (default: 8.8.8.8) and return the round-trip latency
  /// in milliseconds, or `null` if the host is unreachable.
  Future<int?> ping(String host);
}
