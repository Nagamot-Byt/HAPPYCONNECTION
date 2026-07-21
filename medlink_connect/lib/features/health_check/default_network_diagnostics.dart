import 'package:flutter/services.dart';
import 'package:medlink_connect/core/network_diagnostics.dart';

/// Default [NetworkDiagnostics] implementation that delegates to the host
/// platform via a method channel.
///
/// Channel: `com.medlinkconnect/network_diagnostics`
///
/// Platform implementors must handle:
/// - `flushDns` → Windows: `ipconfig /flushdns`, macOS: `sudo dscacheutil …`,
///   Linux: `systemd-resolve --flush-caches`
/// - `clearNetworkCaches` → combined cache-clear sequence
/// - `ping` → return ms or null
class DefaultNetworkDiagnostics implements NetworkDiagnostics {
  static const _channel = MethodChannel(
    'com.medlinkconnect/network_diagnostics',
  );

  @override
  Future<bool> flushDns() async {
    try {
      final result = await _channel.invokeMethod<bool>('flushDns');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> clearNetworkCaches() async {
    try {
      final result = await _channel.invokeMethod<bool>('clearNetworkCaches');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<int?> ping(String host) async {
    try {
      final result = await _channel.invokeMethod<int>('ping', {'host': host});
      return result;
    } on PlatformException {
      return null;
    }
  }
}
