import 'package:flutter/services.dart';
import 'package:medlink_connect/core/route_manager.dart';

/// Default [RouteManager] implementation that communicates with the native
/// platform via the `com.medlinkconnect/route_manager` method channel.
class DefaultRouteManager implements RouteManager {
  static const _channel = MethodChannel('com.medlinkconnect/route_manager');

  @override
  Future<String> addRoute({
    required String destinationCidr,
    required String gateway,
    required String interfaceName,
  }) async {
    try {
      final result = await _channel.invokeMethod<String>('addRoute', {
        'destinationCidr': destinationCidr,
        'gateway': gateway,
        'interfaceName': interfaceName,
      });
      return result ?? 'Route added.';
    } on PlatformException catch (e) {
      return 'Error adding route: ${e.message}';
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
      return 'Error removing route: ${e.message}';
    }
  }

  @override
  Future<String> enableSplitTunnel({
    required List<String> hospitalSubnets,
    required String gateway,
    required String interfaceName,
  }) async {
    try {
      final result = await _channel.invokeMethod<String>('enableSplitTunnel', {
        'hospitalSubnets': hospitalSubnets,
        'gateway': gateway,
        'interfaceName': interfaceName,
      });
      return result ?? 'Split tunnel enabled.';
    } on PlatformException catch (e) {
      return 'Error enabling split tunnel: ${e.message}';
    }
  }

  @override
  Future<String> disableSplitTunnel() async {
    try {
      final result =
          await _channel.invokeMethod<String>('disableSplitTunnel');
      return result ?? 'Split tunnel disabled.';
    } on PlatformException catch (e) {
      return 'Error disabling split tunnel: ${e.message}';
    }
  }

  @override
  Future<String> getRoutes() async {
    try {
      final result = await _channel.invokeMethod<String>('getRoutes');
      return result ?? '';
    } on PlatformException catch (e) {
      return 'Error fetching routes: ${e.message}';
    }
  }

  @override
  Future<List<String>> listInterfaces() async {
    try {
      final result =
          await _channel.invokeMethod<List<dynamic>>('listInterfaces');
      if (result == null) return [];
      return result.cast<String>();
    } on PlatformException {
      return [];
    }
  }
}
