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

  String? _lastProbeError;

  @override
  String? get lastProbeError => _lastProbeError;

  bool _isPermissionError(PlatformException e) {
    final code = e.code.toLowerCase();
    final message = (e.message ?? '').toLowerCase();
    return code.contains('permiso') ||
        code.contains('privilege') ||
        code.contains('access_denied') ||
        message.contains('administrador') ||
        message.contains('privilegio') ||
        message.contains('sudo');
  }

  MedLinkException _mapPlatformError(PlatformException e, String action) {
    final detail = 'Error $action (${e.code}): ${e.message}';
    return _isPermissionError(e)
        ? PrivilegeRequiredException(detail)
        : NetworkDiagnosticException(detail);
  }

  @override
  Future<String> flushDns() async {
    try {
      final result = await _channel.invokeMethod<String>('flushDns');
      return result ?? 'DNS cache flushed successfully.';
    } on PlatformException catch (e) {
      throw _mapPlatformError(e, 'flushing DNS');
    }
  }

  @override
  Future<String> clearNetworkCaches() async {
    try {
      final result = await _channel.invokeMethod<String>('clearNetworkCaches');
      return result ?? 'Network caches cleared successfully.';
    } on PlatformException catch (e) {
      throw _mapPlatformError(e, 'clearing network caches');
    }
  }

  @override
  Future<int?> ping(String host) async {
    _lastProbeError = null;
    try {
      final result = await _channel.invokeMethod<int>(
          'ping', {'host': host}).timeout(const Duration(seconds: 4));
      return result;
    } on TimeoutException {
      _lastProbeError = 'timeout';
      return null;
    } on MissingPluginException {
      _lastProbeError = 'diagnostics_not_available';
      return null;
    } on PlatformException catch (e) {
      _lastProbeError = '${e.code}: ${e.message}';
      return null;
    } catch (e) {
      _lastProbeError = e.toString();
      return null;
    }
  }

  @override
  Future<int?> checkTcpPort(String host, int port) async {
    _lastProbeError = null;
    try {
      final result = await _channel.invokeMethod<int>('checkTcpPort', {
        'host': host,
        'port': port,
      }).timeout(const Duration(seconds: 4));
      return result;
    } on TimeoutException {
      _lastProbeError = 'timeout';
      return null;
    } on MissingPluginException {
      _lastProbeError = 'diagnostics_not_available';
      return null;
    } on PlatformException catch (e) {
      _lastProbeError = '${e.code}: ${e.message}';
      return null;
    } catch (e) {
      _lastProbeError = e.toString();
      return null;
    }
  }
}
