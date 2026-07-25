import 'package:flutter/services.dart';
import 'package:medlink_connect/core/rdp_launcher.dart';

/// Default [RdpLauncher] implementation that communicates with the native
/// platform via the `com.medlinkconnect/rdp_launcher` method channel.
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
      final result =
          await _channel.invokeMethod<bool>('isRdpClientAvailable');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }
}
