import 'package:injectable/injectable.dart';
import 'package:flutter/services.dart';
import 'package:medlink_connect/core/exceptions.dart';
import 'package:medlink_connect/core/rdp_launcher.dart';

/// Default [RdpLauncher] implementation that communicates with the native
/// platform via the `com.medlinkconnect/rdp_launcher` method channel.
@LazySingleton(as: RdpLauncher)
class DefaultRdpLauncher implements RdpLauncher {
  static const _channel = MethodChannel('com.medlinkconnect/rdp_launcher');

  @override
  Future<bool> preLaunch() async {
    try {
      final result = await _channel.invokeMethod<bool>('preLaunch');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> isRdpClientAvailable() async {
    try {
      final result = await _channel.invokeMethod<bool>('isRdpClientAvailable');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<String> launchRdp({
    required String host,
    int port = 3389,
    String? username,
    String? domain,
    bool useWebFeed = false,
    String profile = 'adaptive',
    int? measuredLatencyMs,
  }) async {
    if (host.trim().isEmpty) {
      throw ArgumentError.value(
          host, 'host', 'El host RDP no puede estar vacío');
    }
    if (port <= 0 || port > 65535) {
      throw ArgumentError.value(port, 'port', 'Puerto RDP inválido');
    }

    try {
      final result = await _channel.invokeMethod<String>('launchRdp', {
        'host': host.trim(),
        'port': port,
        'username': username?.trim(),
        'domain': domain?.trim(),
        'useWebFeed': useWebFeed,
        'profile': profile,
        'measuredLatencyMs': measuredLatencyMs,
      });
      return result ?? 'Conexión RDP lanzada exitosamente.';
    } on PlatformException catch (e) {
      final message =
          e.message?.isNotEmpty == true ? e.message! : 'Error desconocido';
      final code = e.code;
      throw RdpLaunchException('Error al lanzar RDP ($code): $message');
    }
  }
}
