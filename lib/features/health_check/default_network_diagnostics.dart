import 'dart:async';
import 'package:injectable/injectable.dart';
import 'package:flutter/services.dart';
import 'package:medlink_connect/core/exceptions.dart';
import 'package:medlink_connect/core/network_diagnostics.dart';

/// Default [NetworkDiagnostics] implementation that communicates with the
/// native platform via the `com.medlinkconnect/network_diagnostics` method
/// channel.
@LazySingleton(as: NetworkDiagnostics)
class DefaultNetworkDiagnostics implements NetworkDiagnostics {
  static const _channel =
      MethodChannel('com.medlinkconnect/network_diagnostics');

  @override
  Future<String> flushDns() async {
    try {
      final result = await _channel.invokeMethod<String>('flushDns');
      return result ?? 'DNS cache flushed successfully.';
    } on PlatformException catch (e) {
      throw NetworkDiagnosticException(
          'Error flushing DNS (${e.code}): ${e.message}');
    }
  }

  @override
  Future<String> clearNetworkCaches() async {
    try {
      final result = await _channel.invokeMethod<String>('clearNetworkCaches');
      return result ?? 'Network caches cleared successfully.';
    } on PlatformException catch (e) {
      throw NetworkDiagnosticException(
          'Error clearing network caches (${e.code}): ${e.message}');
    }
  }

  @override
  Future<int?> ping(String host) async {
    try {
      final result = await _channel.invokeMethod<int>(
          'ping', {'host': host}).timeout(const Duration(seconds: 4));
      return result;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<int?> checkTcpPort(String host, int port) async {
    try {
      final result = await _channel.invokeMethod<int>('checkTcpPort', {
        'host': host,
        'port': port,
      }).timeout(const Duration(seconds: 4));
      return result;
    } catch (_) {
      return null;
    }
  }
}
