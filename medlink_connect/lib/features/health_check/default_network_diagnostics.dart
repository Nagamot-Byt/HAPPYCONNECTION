import 'package:flutter/services.dart';
import 'package:medlink_connect/core/network_diagnostics.dart';

/// Default [NetworkDiagnostics] implementation that communicates with the
/// native platform via the `com.medlinkconnect/network_diagnostics` method
/// channel.
class DefaultNetworkDiagnostics implements NetworkDiagnostics {
  static const _channel =
      MethodChannel('com.medlinkconnect/network_diagnostics');

  @override
  Future<String> flushDns() async {
    try {
      final result = await _channel.invokeMethod<String>('flushDns');
      return result ?? 'DNS cache flushed successfully.';
    } on PlatformException catch (e) {
      return 'Error flushing DNS: ${e.message}';
    }
  }

  @override
  Future<String> clearNetworkCaches() async {
    try {
      final result =
          await _channel.invokeMethod<String>('clearNetworkCaches');
      return result ?? 'Network caches cleared successfully.';
    } on PlatformException catch (e) {
      return 'Error clearing network caches: ${e.message}';
    }
  }

  @override
  Future<int?> ping(String host) async {
    try {
      final result = await _channel.invokeMethod<int>('ping', {'host': host});
      return result;
    } on PlatformException {
      return null; // host unreachable
    }
  }
}
