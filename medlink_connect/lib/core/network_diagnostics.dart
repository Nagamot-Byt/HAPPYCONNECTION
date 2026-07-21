import 'network_diagnostics_result.dart';

/// Abstract interface for OS-level network diagnostics.
///
/// Each platform provides its own implementation via a platform channel.
/// This interface exposes the operations the UI layer needs — never the
/// underlying shell commands or platform APIs directly.
abstract class NetworkDiagnostics {
  /// Flush the DNS cache on the current platform.
  ///
  /// Returns `true` if the flush succeeded (or was a no-op), `false` on error.
  /// Throws [NetworkDiagnosticsException] only for fatal platform errors.
  Future<bool> flushDns();

  /// Clear system network caches (ARP, routing table cache, etc.).
  ///
  /// Returns `true` on success or no-op. Returns `false` on failure.
  Future<bool> clearNetworkCaches();

  /// Ping [host] (default: 8.8.8.8) with [count] attempts and [timeoutMs]
  /// per attempt, and return the round-trip latency in milliseconds.
  ///
  /// Returns `null` if the host is unreachable or all attempts fail.
  /// Retries internally once (with a 1-second delay) before reporting failure.
  Future<int?> ping(
    String host, {
    int count,
    int timeoutMs,
  });

  /// Run all three diagnostics (DNS flush, cache clear, ping) and return a
  /// structured [NetworkDiagnosticsResult].
  ///
  /// This is the preferred convenience method for the UI layer.
  /// It never throws — errors are captured in the result fields.
  Future<NetworkDiagnosticsResult> runFullDiagnostics({
    String pingHost = '8.8.8.8',
    int pingCount = 4,
    int pingTimeoutMs = 2000,
  });
}
