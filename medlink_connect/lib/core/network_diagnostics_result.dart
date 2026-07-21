/// Structured result from a full network diagnostics run.
///
/// Contains results from DNS flush, network cache clear, and ping test.
/// The [isHealthy] flag is true only when DNS and cache operations
/// succeeded *and* the ping reached the target host.
class NetworkDiagnosticsResult {
  /// Whether the DNS flush succeeded (or was a no-op on mobile).
  final bool dnsFlushed;

  /// Whether the network cache clear succeeded (or was a no-op on mobile).
  final bool cachesCleared;

  /// Round-trip latency in milliseconds, or null if the ping failed.
  final int? pingLatencyMs;

  /// Human-readable description of why ping failed, if applicable.
  final String? pingError;

  /// The host that was pinged.
  final String pingHost;

  /// Number of ping attempts sent.
  final int pingCount;

  /// Ping timeout in milliseconds per attempt.
  final int pingTimeoutMs;

  const NetworkDiagnosticsResult({
    required this.dnsFlushed,
    required this.cachesCleared,
    this.pingLatencyMs,
    this.pingError,
    this.pingHost = '8.8.8.8',
    this.pingCount = 4,
    this.pingTimeoutMs = 2000,
  });

  /// True when DNS + cache + ping all succeeded.
  bool get isHealthy => dnsFlushed && cachesCleared && pingLatencyMs != null;

  /// Human-readable summary in English (core logic) or Spanish (end-user).
  String summary({bool spanish = false}) {
    if (isHealthy) {
      return spanish
          ? '✅ Red lista — ${pingLatencyMs} ms a $pingHost'
          : '✅ Network ready — ${pingLatencyMs} ms to $pingHost';
    }
    final buf = StringBuffer(spanish ? '⚠ Problemas detectados:' : '⚠ Issues detected:');
    if (!dnsFlushed) {
      buf.write(spanish ? ' DNS no vaciado;' : ' DNS not flushed;');
    }
    if (!cachesCleared) {
      buf.write(spanish ? ' Cachés no limpiados;' : ' Caches not cleared;');
    }
    if (pingLatencyMs == null) {
      buf.write(spanish
          ? ' Sin conectividad a $pingHost'
          : ' No connectivity to $pingHost');
      if (pingError != null) {
        buf.write(' ($pingError)');
      }
      buf.write(';');
    }
    return buf.toString();
  }

  @override
  String toString() => summary();
}
