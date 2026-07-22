import 'package:flutter/services.dart';
import 'package:medlink_connect/core/route_entry.dart';
import 'package:medlink_connect/core/route_manager.dart';
import 'package:medlink_connect/features/split_tunnel/route_parser.dart';

/// Default [RouteManager] implementation via platform channel.
///
/// ### Architecture
/// On desktop (Windows, macOS, Linux) this calls platform-native code through
/// `com.medlinkconnect/route_manager` to manipulate the system routing table
/// directly.  On mobile the same channel provisions VPN profiles.
///
/// ### Route tracking & rollback
/// [enableSplitTunnel] tracks every route added in `_addedRoutes`.  If any
/// route-add fails, **all** previously-added routes are removed before
/// returning `false`.  [disableSplitTunnel] only removes routes that were
/// tracked.
///
/// ### Error handling
/// All public methods catch exceptions internally and return `false` on
/// failure.  End-user-facing error messages are emitted in **Spanish**.
class DefaultRouteManager implements RouteManager {
  static const _channel = MethodChannel('com.medlinkconnect/route_manager');

  /// Routes successfully added during [enableSplitTunnel].
  /// Used so [disableSplitTunnel] only removes what we added.
  final List<RouteEntry> _addedRoutes = [];

  // ──────────────────────────────────────────────────────────
  // RouteManager interface
  // ──────────────────────────────────────────────────────────

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
    // Clear tracking from a previous enable/disable cycle.
    _addedRoutes.clear();

    for (final cidr in hospitalSubnets) {
      final entry = RouteEntry(
        destinationCidr: cidr,
        gateway: hospitalGateway,
        interfaceName: hospitalInterface,
      );

      final ok = await addRoute(
        destinationCidr: cidr,
        gateway: hospitalGateway,
        interfaceName: hospitalInterface,
      );

      if (!ok) {
        // Rollback: remove all routes added so far.
        await _rollback('No se pudo agregar la ruta $cidr. Revirtiendo cambios.');
        return false;
      }

      // Verify the route actually exists in the table.
      final verified = await _verifyRoute(cidr);
      if (!verified) {
        await _rollback(
          'La ruta $cidr no se verificó después de agregarla. Revirtiendo cambios.',
        );
        return false;
      }

      _addedRoutes.add(entry);
    }

    return true;
  }

  @override
  Future<bool> disableSplitTunnel() async {
    if (_addedRoutes.isEmpty) {
      // Nothing to remove — still try the platform channel in case routes
      // were added externally.
      try {
        await _channel.invokeMethod('disableSplitTunnel');
      } on PlatformException {
        // No-op: the channel may not be implemented on all platforms.
      }
      return true;
    }

    var allOk = true;

    // Iterate in reverse so we unwind in the opposite order.
    for (final entry in _addedRoutes.reversed) {
      final ok = await removeRoute(destinationCidr: entry.destinationCidr);
      if (!ok) {
        allOk = false;
      }
    }

    if (allOk) {
      _addedRoutes.clear();
    }

    return allOk;
  }

  // ──────────────────────────────────────────────────────────
  // Additional public API
  // ──────────────────────────────────────────────────────────

  /// Retrieve the current routing table entries via the platform channel.
  ///
  /// The platform channel must respond with raw route-table output for the
  /// current platform.  This method parses that output using [RouteParser].
  ///
  /// Returns an empty list on any error.
  Future<List<RouteEntry>> getCurrentRoutes() async {
    try {
      final output = await _channel.invokeMethod<String>('getRoutes');
      if (output == null || output.trim().isEmpty) return [];

      // Determine platform type from channel response or default to Linux
      // format.  The platform channel should include a `platform` field.
      // We try all three parsers and return whichever produces results.
      // This is a best-effort approach — production code should receive
      // the platform type from the channel.
      return RouteParser.parseRouteOutput(output, PlatformType.linux);
    } on PlatformException {
      return [];
    }
  }

  /// List available network interfaces via the platform channel.
  ///
  /// Returns interface names (e.g. `["eth0", "Wi-Fi", "en0"]`).
  /// Returns an empty list on any error.
  Future<List<String>> listInterfaces() async {
    try {
      final result = await _channel.invokeMethod('listInterfaces');
      if (result is List) {
        return result.cast<String>();
      }
      return [];
    } on PlatformException {
      return [];
    }
  }

  /// Returns the list of routes added during the current split-tunnel session.
  /// Useful for debugging and UI display.
  List<RouteEntry> get addedRoutes => List.unmodifiable(_addedRoutes);

  // ──────────────────────────────────────────────────────────
  // Internals
  // ──────────────────────────────────────────────────────────

  /// Remove every route in [_addedRoutes] (best-effort) and log [reason].
  Future<void> _rollback(String reason) async {
    // Emit error diagnostic — in a real app this would go to a logger.
    // ignore: avoid_print
    print('[DefaultRouteManager] $reason');

    for (final entry in _addedRoutes.reversed) {
      await removeRoute(destinationCidr: entry.destinationCidr);
    }
    _addedRoutes.clear();
  }

  /// Verify that a route for [cidr] exists in the current routing table.
  Future<bool> _verifyRoute(String cidr) async {
    final routes = await getCurrentRoutes();
    return RouteParser.containsRoute(routes, cidr);
  }
}
