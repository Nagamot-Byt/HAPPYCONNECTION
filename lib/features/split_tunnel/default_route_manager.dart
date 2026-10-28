import 'package:injectable/injectable.dart';
import 'package:flutter/services.dart';
import 'package:medlink_connect/core/exceptions.dart';
import 'package:medlink_connect/core/route_manager.dart';

/// Default [RouteManager] implementation that communicates with the native
/// platform via the `com.medlinkconnect/route_manager` method channel.
@LazySingleton(as: RouteManager)
class DefaultRouteManager implements RouteManager {
  static const _channel = MethodChannel('com.medlinkconnect/route_manager');

  bool _isValidIpv4(String ip) {
    final regex = RegExp(r'^((25[0-5]|(2[0-4]|1\d|[1-9]|)\d)\.?\b){4}$');
    return regex.hasMatch(ip);
  }

  bool _isValidCidr(String cidr) {
    final parts = cidr.split('/');
    if (parts.length != 2) return _isValidIpv4(cidr);
    if (!_isValidIpv4(parts[0])) return false;
    final prefix = int.tryParse(parts[1]);
    return prefix != null && prefix >= 0 && prefix <= 32;
  }

  @override
  Future<String> addRoute({
    required String destinationCidr,
    required String gateway,
    required String interfaceName,
  }) async {
    if (!_isValidCidr(destinationCidr)) {
      throw const RouteConfigurationException(
          'Validación fallida: destinationCidr no es un formato válido IPv4/CIDR.');
    }
    if (!_isValidIpv4(gateway)) {
      throw const RouteConfigurationException(
          'Validación fallida: gateway no es una IP válida.');
    }
    try {
      final result = await _channel.invokeMethod<String>('addRoute', {
        'destinationCidr': destinationCidr,
        'gateway': gateway,
        'interfaceName': interfaceName,
      });
      return result ?? 'Route added.';
    } on PlatformException catch (e) {
      throw RouteConfigurationException(
          'Error adding route (${e.code}): ${e.message}');
    }
  }

  @override
  Future<String> removeRoute({required String destinationCidr}) async {
    try {
      final result = await _channel.invokeMethod<String>(
        'removeRoute',
        {'destinationCidr': destinationCidr},
      );
      return result ?? 'Route removed.';
    } on PlatformException catch (e) {
      throw RouteConfigurationException(
          'Error removing route (${e.code}): ${e.message}');
    }
  }

  @override
  Future<String> enableSplitTunnel({
    required List<String> hospitalSubnets,
    required String gateway,
    required String interfaceName,
  }) async {
    for (final subnet in hospitalSubnets) {
      if (!_isValidCidr(subnet)) {
        throw RouteConfigurationException(
            'Validación fallida: la subred $subnet no es un formato válido IPv4/CIDR.');
      }
    }
    if (!_isValidIpv4(gateway)) {
      throw const RouteConfigurationException(
          'Validación fallida: gateway no es una IP válida.');
    }
    try {
      final result = await _channel.invokeMethod<String>('enableSplitTunnel', {
        'hospitalSubnets': hospitalSubnets,
        'gateway': gateway,
        'interfaceName': interfaceName,
      });
      return result ?? 'Split tunnel enabled.';
    } on PlatformException catch (e) {
      throw RouteConfigurationException(
          'Error enabling split tunnel (${e.code}): ${e.message}');
    }
  }

  @override
  Future<String> disableSplitTunnel() async {
    try {
      final result = await _channel.invokeMethod<String>('disableSplitTunnel');
      return result ?? 'Split tunnel disabled.';
    } on PlatformException catch (e) {
      throw RouteConfigurationException(
          'Error disabling split tunnel (${e.code}): ${e.message}');
    }
  }

  @override
  Future<String> getRoutes() async {
    try {
      final result = await _channel.invokeMethod<String>('getRoutes');
      return result ?? '';
    } on PlatformException catch (e) {
      throw RouteConfigurationException(
          'Error fetching routes (${e.code}): ${e.message}');
    }
  }

  @override
  Future<Map<String, String>> getPrimaryDefaultRouteInfo() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getPrimaryDefaultRouteInfo',
      );
      if (result == null) {
        return const <String, String>{};
      }
      return result.map(
        (key, value) => MapEntry(
          key.toString(),
          value?.toString() ?? '',
        ),
      );
    } on PlatformException catch (e) {
      throw RouteConfigurationException(
        'Error fetching default route info (${e.code}): ${e.message}',
      );
    }
  }

  @override
  Future<List<String>> listInterfaces() async {
    try {
      final result =
          await _channel.invokeMethod<List<dynamic>>('listInterfaces');
      if (result == null) return [];
      return result.cast<String>();
    } on PlatformException catch (e) {
      throw RouteConfigurationException(
          'Error listing interfaces (${e.code}): ${e.message}');
    }
  }

  @override
  Future<List<String>> verifyRoutes({
    required List<String> hospitalSubnets,
    required String gateway,
    required String interfaceName,
  }) async {
    try {
      final result =
          await _channel.invokeMethod<List<dynamic>>('verifyRoutes', {
        'hospitalSubnets': hospitalSubnets,
        'gateway': gateway,
        'interfaceName': interfaceName,
      });
      if (result == null) return const <String>[];
      final missing = result.cast<String>();
      // Si hay rutas faltantes, dar un pequeño margen y reintentar una vez
      if (missing.isNotEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 800));
        final retry =
            await _channel.invokeMethod<List<dynamic>>('verifyRoutes', {
          'hospitalSubnets': hospitalSubnets,
          'gateway': gateway,
          'interfaceName': interfaceName,
        });
        if (retry == null) return missing;
        return retry.cast<String>();
      }
      return missing;
    } on PlatformException catch (e) {
      throw RouteConfigurationException(
          'Error verifying routes (${e.code}): ${e.message}');
    }
  }
}
