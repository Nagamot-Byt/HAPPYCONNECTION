import 'package:flutter/services.dart';
import 'package:medlink_connect/core/route_manager.dart';

/// Default [RouteManager] implementation via platform channel.
///
/// Channel: `com.medlinkconnect/route_manager`
///
/// Platform implementors must handle:
/// - `addRoute` / `removeRoute` — OS routing table commands
/// - `enableSplitTunnel` / `disableSplitTunnel` — desktop: policy routing;
///   mobile: VPN profile provisioning
class DefaultRouteManager implements RouteManager {
  static const _channel = MethodChannel('com.medlinkconnect/route_manager');

  @override
  Future<bool> addRoute({
    required String destinationCidr,
    required String gateway,
    required String interfaceName,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('addRoute', {
        'destinationCidr': destinationCidr,
        'gateway': gateway,
        'interfaceName': interfaceName,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> removeRoute({required String destinationCidr}) async {
    try {
      final result = await _channel.invokeMethod<bool>('removeRoute', {
        'destinationCidr': destinationCidr,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> enableSplitTunnel({
    required List<String> hospitalSubnets,
    required String hospitalGateway,
    required String hospitalInterface,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('enableSplitTunnel', {
        'hospitalSubnets': hospitalSubnets,
        'hospitalGateway': hospitalGateway,
        'hospitalInterface': hospitalInterface,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> disableSplitTunnel() async {
    try {
      final result = await _channel.invokeMethod<bool>('disableSplitTunnel');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }
}
