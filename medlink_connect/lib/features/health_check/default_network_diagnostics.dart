import 'dart:async';
import 'package:flutter/services.dart';
import 'package:medlink_connect/core/network_diagnostics.dart';
import 'package:medlink_connect/core/network_diagnostics_exception.dart';
import 'package:medlink_connect/core/network_diagnostics_result.dart';
import 'package:medlink_connect/features/health_check/ping_parser.dart';

/// Default [NetworkDiagnostics] implementation that delegates to the host
/// platform via a method channel.
///
/// Channel: `com.medlinkconnect/network_diagnostics`
///
/// Platform implementors handle:
/// - **flushDns** → Windows: `ipconfig /flushdns`, macOS: `sudo dscacheutil …`,
///   Linux: `resolvectl flush-caches`, iOS/Android: no-op
/// - **clearNetworkCaches** → Windows: `arp -d *` + `netsh … delete arpcache`,
///   macOS: `sudo arp -ad`, Linux: `sudo ip neigh flush all`, mobile: no-op
/// - **ping** → Windows: `ping -n {count} -w {timeout} {host}`,
///   macOS/Linux: `ping -c {count} -W {timeout} {host}`,
///   mobile: TCP connect to port 3389 or DNS resolution proxy
///
/// On desktop, if the platform plugin reports that elevation is needed,
/// callers should prompt the user before retrying.
class DefaultNetworkDiagnostics implements NetworkDiagnostics {
  static const _channel = MethodChannel(
    'com.medlinkconnect/network_diagnostics',
  );

  /// Maximum time to wait for any single platform channel invocation.
  static const Duration _invokeTimeout = Duration(seconds: 15);

  @override
  Future<bool> flushDns() async {
    try {
      final result = await _channel
          .invokeMethod<bool>('flushDns')
          .timeout(_invokeTimeout);
      return result ?? false;
    } on MissingPluginException {
      // Platform doesn't implement the channel at all — fail gracefully.
      _log('flushDns: platform channel not implemented');
      return false;
    } on PlatformException catch (e) {
      if (_isElevationError(e)) {
        _log('flushDns: elevation required — ${e.message}');
        throw NetworkDiagnosticsException(
          NetworkDiagnosticsErrorCode.elevationRequired,
          message: 'DNS flush requires administrator privileges.',
          cause: e,
        );
      }
      _log('flushDns: platform error — ${e.message}');
      return false;
    } on TimeoutException {
      _log('flushDns: timed out');
      return false;
    } catch (e) {
      _log('flushDns: unexpected error — $e');
      return false;
    }
  }

  @override
  Future<bool> clearNetworkCaches() async {
    try {
      final result = await _channel
          .invokeMethod<bool>('clearNetworkCaches')
          .timeout(_invokeTimeout);
      return result ?? false;
    } on MissingPluginException {
      _log('clearNetworkCaches: platform channel not implemented');
      return false;
    } on PlatformException catch (e) {
      if (_isElevationError(e)) {
        _log('clearNetworkCaches: elevation required — ${e.message}');
        throw NetworkDiagnosticsException(
          NetworkDiagnosticsErrorCode.elevationRequired,
          message: 'Cache clear requires administrator privileges.',
          cause: e,
        );
      }
      _log('clearNetworkCaches: platform error — ${e.message}');
      return false;
    } on TimeoutException {
      _log('clearNetworkCaches: timed out');
      return false;
    } catch (e) {
      _log('clearNetworkCaches: unexpected error — $e');
      return false;
    }
  }

  @override
  Future<int?> ping(
    String host, {
    int count = 4,
    int timeoutMs = 2000,
  }) async {
    try {
      // First attempt
      var result = await _pingInternal(host, count, timeoutMs);
      if (result != null) return result;

      // Retry once after 1 second
      _log('ping: first attempt failed, retrying in 1s…');
      await Future.delayed(const Duration(seconds: 1));
      result = await _pingInternal(host, count, timeoutMs);
      return result;
    } on NetworkDiagnosticsException {
      rethrow;
    } catch (e) {
      _log('ping: unexpected error — $e');
      return null;
    }
  }

  Future<int?> _pingInternal(String host, int count, int timeoutMs) async {
    try {
      final result = await _channel
          .invokeMethod<dynamic>('ping', {
        'host': host,
        'count': count,
        'timeoutMs': timeoutMs,
      }).timeout(Duration(milliseconds: timeoutMs * count + 5000));

      if (result == null) return null;

      // If the platform returns an integer directly, it's the avg latency.
      if (result is int) return result;
      if (result is double) return result.round();

      // If the platform returns a map with parsed stats…
      if (result is Map) {
        return PingParser.parseStatsMap(result);
      }

      return null;
    } on MissingPluginException {
      _log('ping: platform channel not implemented');
      return null;
    } on PlatformException catch (e) {
      _log('ping: platform error — ${e.message}');
      return null;
    } on TimeoutException {
      _log('ping: timed out');
      return null;
    }
  }

  @override
  Future<NetworkDiagnosticsResult> runFullDiagnostics({
    String pingHost = '8.8.8.8',
    int pingCount = 4,
    int pingTimeoutMs = 2000,
  }) async {
    bool dnsFlushed = false;
    bool cachesCleared = false;
    int? pingLatencyMs;
    String? pingError;

    // DNS flush — never throw, capture result
    try {
      dnsFlushed = await flushDns();
    } on NetworkDiagnosticsException catch (e) {
      pingError = e.message;
    } catch (e) {
      pingError = 'DNS flush failed: $e';
    }

    // Cache clear — never throw, capture result
    try {
      cachesCleared = await clearNetworkCaches();
    } on NetworkDiagnosticsException catch (e) {
      // Only overwrite pingError if it isn't already set
      if (pingError == null) pingError = e.message;
    } catch (e) {
      if (pingError == null) pingError = 'Cache clear failed: $e';
    }

    // Ping
    try {
      pingLatencyMs = await ping(
        pingHost,
        count: pingCount,
        timeoutMs: pingTimeoutMs,
      );
    } on NetworkDiagnosticsException catch (e) {
      if (pingError == null) pingError = e.message;
    } catch (e) {
      if (pingError == null) pingError = 'Ping failed: $e';
    }

    return NetworkDiagnosticsResult(
      dnsFlushed: dnsFlushed,
      cachesCleared: cachesCleared,
      pingLatencyMs: pingLatencyMs,
      pingError: pingError,
      pingHost: pingHost,
      pingCount: pingCount,
      pingTimeoutMs: pingTimeoutMs,
    );
  }

  // --- helpers -------------------------------------------------------------

  /// Heuristic to detect elevation-related errors from the platform channel.
  static bool _isElevationError(PlatformException e) {
    final code = e.code.toLowerCase();
    final msg = (e.message ?? '').toLowerCase();
    return code.contains('elevation') ||
        code.contains('permission') ||
        code.contains('access_denied') ||
        msg.contains('elevation required') ||
        msg.contains('permission denied') ||
        msg.contains('administrator') ||
        msg.contains('root') ||
        msg.contains('sudo');
  }

  static void _log(String msg) {
    // In production this would use a proper logger; for now stderr is fine.
    // ignore: avoid_print
    print('[NetworkDiagnostics] $msg');
  }
}
