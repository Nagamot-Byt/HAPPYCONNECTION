import 'package:injectable/injectable.dart';
import 'package:flutter/services.dart';
import 'package:medlink_connect/core/exceptions.dart';
import 'package:medlink_connect/core/input_sanitizer.dart';
import 'package:medlink_connect/core/route_manager.dart';

/// Default [RouteManager] implementation that communicates with the native
/// platform via the `com.medlinkconnect/route_manager` method channel.
@LazySingleton(as: RouteManager)
class DefaultRouteManager implements RouteManager {
  static const _channel = MethodChannel('com.medlinkconnect/route_manager');

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

  MedLinkException _routePlatformError(PlatformException e, String detail) {
    return _isPermissionError(e)
        ? PrivilegeRequiredException(detail)
        : RouteConfigurationException(detail);
  }

  @override
  Future<String> addRoute({
    required String destinationCidr,
    required String gateway,
    required String interfaceName,
  }) async {
    final String sanitizedCidr;
    final String sanitizedGateway;
    final String sanitizedIface;
    try {
      sanitizedCidr = InputSanitizer.sanitizeCidr(
        destinationCidr,
        fieldName: 'destinationCidr',
      );
      sanitizedGateway = InputSanitizer.sanitizeIpv4(
        gateway,
        fieldName: 'gateway',
      );
      sanitizedIface = InputSanitizer.sanitizeInterfaceName(
        interfaceName,
        fieldName: 'interfaceName',
      );
    } on ArgumentError catch (e) {
      throw RouteConfigurationException(
        'Route validation failed: ${e.message}',
      );
    }
    try {
      final result = await _channel.invokeMethod<String>('addRoute', {
        'destinationCidr': sanitizedCidr,
        'gateway': sanitizedGateway,
        'interfaceName': sanitizedIface,
      });
      return result ?? 'Route added.';
    } on PlatformException catch (e) {
      throw _routePlatformError(
          e, 'Error adding route (${e.code}): ${e.message}');
    }
  }

  @override
  Future<String> removeRoute({
    required String destinationCidr,
    String? gateway,
    String? interfaceName,
  }) async {
    final bool hasGateway = gateway != null && gateway.isNotEmpty;
    final bool hasInterface = interfaceName != null && interfaceName.isNotEmpty;
    if (hasGateway != hasInterface) {
      throw const RouteConfigurationException(
          'An exact route cleanup requires both gateway and interface.');
    }
    final String sanitizedCidr;
    String? sanitizedGateway;
    String? sanitizedIface;
    try {
      sanitizedCidr = InputSanitizer.sanitizeCidr(
        destinationCidr,
        fieldName: 'destinationCidr',
      );
      if (hasGateway) {
        sanitizedGateway = InputSanitizer.sanitizeIpv4(
          gateway,
          fieldName: 'gateway',
        );
      }
      if (hasInterface) {
        sanitizedIface = InputSanitizer.sanitizeInterfaceName(
          interfaceName,
          fieldName: 'interfaceName',
        );
      }
    } on ArgumentError catch (e) {
      throw RouteConfigurationException(
        'Route validation failed: ${e.message}',
      );
    }
    try {
      final result = await _channel.invokeMethod<String>('removeRoute', {
        'destinationCidr': sanitizedCidr,
        if (hasGateway) 'gateway': sanitizedGateway,
        if (hasInterface) 'interfaceName': sanitizedIface,
      });
      return result ?? 'Route removed.';
    } on PlatformException catch (e) {
      throw _routePlatformError(
          e, 'Error removing route (${e.code}): ${e.message}');
    }
  }

  @override
  Future<String> enableSplitTunnel({
    required List<String> hospitalSubnets,
    required String gateway,
    required String interfaceName,
  }) async {
    final List<String> sanitizedSubnets;
    final String sanitizedGateway;
    final String sanitizedIface;
    try {
      sanitizedSubnets = InputSanitizer.sanitizeSubnets(
        hospitalSubnets,
        fieldName: 'hospitalSubnets',
        allowEmpty: true,
      );
      sanitizedGateway = InputSanitizer.sanitizeIpv4(
        gateway,
        fieldName: 'gateway',
      );
      sanitizedIface = InputSanitizer.sanitizeInterfaceName(
        interfaceName,
        fieldName: 'interfaceName',
      );
    } on ArgumentError catch (e) {
      throw RouteConfigurationException(
        'Route validation failed: ${e.message}',
      );
    }
    try {
      final result = await _channel.invokeMethod<String>('enableSplitTunnel', {
        'hospitalSubnets': sanitizedSubnets,
        'gateway': sanitizedGateway,
        'interfaceName': sanitizedIface,
      });
      return result ?? 'Split tunnel enabled.';
    } on PlatformException catch (e) {
      throw _routePlatformError(
          e, 'Error enabling split tunnel (${e.code}): ${e.message}');
    }
  }

  @override
  Future<String> disableSplitTunnel() async {
    try {
      final result = await _channel.invokeMethod<String>('disableSplitTunnel');
      return result ?? 'Split tunnel disabled.';
    } on PlatformException catch (e) {
      throw _routePlatformError(
          e, 'Error disabling split tunnel (${e.code}): ${e.message}');
    }
  }

  @override
  Future<String> getRoutes() async {
    try {
      final result = await _channel.invokeMethod<String>('getRoutes');
      return result ?? '';
    } on PlatformException catch (e) {
      throw _routePlatformError(
          e, 'Error fetching routes (${e.code}): ${e.message}');
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
      throw _routePlatformError(
        e,
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
      throw _routePlatformError(
          e, 'Error listing interfaces (${e.code}): ${e.message}');
    }
  }

  @override
  Future<List<String>> verifyRoutes({
    required List<String> hospitalSubnets,
    required String gateway,
    required String interfaceName,
  }) async {
    final List<String> sanitizedSubnets;
    final String sanitizedGateway;
    final String sanitizedIface;
    try {
      sanitizedSubnets = InputSanitizer.sanitizeSubnets(
        hospitalSubnets,
        fieldName: 'subnets',
      );
      sanitizedGateway = InputSanitizer.sanitizeIpv4(
        gateway,
        fieldName: 'gateway',
      );
      sanitizedIface = InputSanitizer.sanitizeInterfaceName(
        interfaceName,
        fieldName: 'interfaceName',
      );
    } on ArgumentError catch (e) {
      throw RouteConfigurationException(
        'Route verification failed: ${e.message}',
      );
    }
    try {
      final result =
          await _channel.invokeMethod<List<dynamic>>('verifyRoutes', {
        'hospitalSubnets': sanitizedSubnets,
        'gateway': sanitizedGateway,
        'interfaceName': sanitizedIface,
      });
      if (result == null) return const <String>[];
      final missing = result.cast<String>();
      // Si hay rutas faltantes, dar un pequeño margen y reintentar una vez
      if (missing.isNotEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 800));
        final retry =
            await _channel.invokeMethod<List<dynamic>>('verifyRoutes', {
          'hospitalSubnets': sanitizedSubnets,
          'gateway': sanitizedGateway,
          'interfaceName': sanitizedIface,
        });
        if (retry == null) return missing;
        return retry.cast<String>();
      }
      return missing;
    } on PlatformException catch (e) {
      throw _routePlatformError(
          e, 'Error verifying routes (${e.code}): ${e.message}');
    }
  }
}
