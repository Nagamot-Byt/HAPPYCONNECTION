import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlink_connect/features/split_tunnel/default_route_manager.dart';

void main() {
  late DefaultRouteManager manager;

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    manager = DefaultRouteManager();
    // Reset mock channel between tests.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.medlinkconnect/route_manager'),
      null,
    );
  });

  /// Helper to set a mock handler that responds to a specific set of calls.
  void mockChannel(
    Future<dynamic> Function(MethodCall call) handler,
  ) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.medlinkconnect/route_manager'),
      handler,
    );
  }

  // ──────────────────────────────────────────────────────────
  // addRoute
  // ──────────────────────────────────────────────────────────

  group('addRoute', () {
    test('sends correct channel arguments', () async {
      dynamic capturedArgs;
      mockChannel((call) async {
        expect(call.method, 'addRoute');
        capturedArgs = call.arguments;
        return true;
      });

      await manager.addRoute(
        destinationCidr: '10.0.0.0/8',
        gateway: '10.0.0.1',
        interfaceName: 'eth0',
      );

      final args = capturedArgs as Map;
      expect(args['destinationCidr'], '10.0.0.0/8');
      expect(args['gateway'], '10.0.0.1');
      expect(args['interfaceName'], 'eth0');
    });

    test('returns true when channel returns true', () async {
      mockChannel((_) async => true);
      final result = await manager.addRoute(
        destinationCidr: '10.0.0.0/8',
        gateway: '10.0.0.1',
        interfaceName: 'eth0',
      );
      expect(result, true);
    });

    test('returns false on PlatformException', () async {
      mockChannel((_) async {
        throw PlatformException(code: 'unknown');
      });
      final result = await manager.addRoute(
        destinationCidr: '10.0.0.0/8',
        gateway: '10.0.0.1',
        interfaceName: 'eth0',
      );
      expect(result, false);
    });
  });

  // ──────────────────────────────────────────────────────────
  // removeRoute
  // ──────────────────────────────────────────────────────────

  group('removeRoute', () {
    test('sends destinationCidr in channel arguments', () async {
      dynamic capturedArgs;
      mockChannel((call) async {
        expect(call.method, 'removeRoute');
        capturedArgs = call.arguments;
        return true;
      });

      await manager.removeRoute(destinationCidr: '10.0.0.0/8');
      final args = capturedArgs as Map;
      expect(args['destinationCidr'], '10.0.0.0/8');
    });

    test('returns false on PlatformException', () async {
      mockChannel((_) async {
        throw PlatformException(code: 'unknown');
      });
      final result = await manager.removeRoute(destinationCidr: '10.0.0.0/8');
      expect(result, false);
    });
  });

  // ──────────────────────────────────────────────────────────
  // enableSplitTunnel / disableSplitTunnel
  // ──────────────────────────────────────────────────────────

  group('enableSplitTunnel', () {
    test('adds all subnets and tracks them', () async {
      final addedCalls = <String>[];
      mockChannel((call) async {
        if (call.method == 'addRoute') {
          addedCalls.add((call.arguments as Map)['destinationCidr']);
          return true;
        }
        if (call.method == 'getRoutes') {
          // Return output that includes the requested CIDR for verification.
          final cidr = addedCalls.last;
          return '$cidr via 10.0.0.1 dev eth0';
        }
        return null;
      });

      final result = await manager.enableSplitTunnel(
        hospitalSubnets: ['10.0.0.0/8', '192.168.100.0/24'],
        hospitalGateway: '10.0.0.1',
        hospitalInterface: 'eth0',
      );

      expect(result, true);
      expect(addedCalls, ['10.0.0.0/8', '192.168.100.0/24']);
      expect(manager.addedRoutes.length, 2);
    });

    test('rolls back all routes on any failure', () async {
      var addCallCount = 0;
      final removedCalls = <String>[];
      mockChannel((call) async {
        if (call.method == 'addRoute') {
          addCallCount++;
          if (addCallCount >= 2) return false; // Second route fails.
          return true;
        }
        if (call.method == 'getRoutes') {
          return '10.0.0.0/8 via 10.0.0.1 dev eth0';
        }
        if (call.method == 'removeRoute') {
          removedCalls.add((call.arguments as Map)['destinationCidr']);
          return true;
        }
        return null;
      });

      final result = await manager.enableSplitTunnel(
        hospitalSubnets: ['10.0.0.0/8', '192.168.100.0/24', '172.16.0.0/12'],
        hospitalGateway: '10.0.0.1',
        hospitalInterface: 'eth0',
      );

      expect(result, false);
      // The first route was added, then second failed, so it was rolled back.
      expect(removedCalls, ['10.0.0.0/8']);
      // Tracking list should be cleared after rollback.
      expect(manager.addedRoutes, isEmpty);
    });

    test('rolls back when route verification fails', () async {
      var addCount = 0;
      final removedCalls = <String>[];
      mockChannel((call) async {
        if (call.method == 'addRoute') {
          addCount++;
          return true;
        }
        if (call.method == 'getRoutes') {
          // First route verifies OK, second verification fails.
          if (addCount <= 1) {
            return '10.0.0.0/8 via 10.0.0.1 dev eth0';
          }
          return ''; // Empty — verification fails.
        }
        if (call.method == 'removeRoute') {
          removedCalls.add((call.arguments as Map)['destinationCidr']);
          return true;
        }
        return null;
      });

      final result = await manager.enableSplitTunnel(
        hospitalSubnets: ['10.0.0.0/8', '192.168.100.0/24'],
        hospitalGateway: '10.0.0.1',
        hospitalInterface: 'eth0',
      );

      expect(result, false);
      expect(removedCalls, contains('10.0.0.0/8'));
      expect(manager.addedRoutes, isEmpty);
    });

    test('never throws — catches all channel errors', () async {
      mockChannel((_) async => throw Exception('Boom!'));

      final result = await manager.enableSplitTunnel(
        hospitalSubnets: ['10.0.0.0/8'],
        hospitalGateway: '10.0.0.1',
        hospitalInterface: 'eth0',
      );

      expect(result, false);
      expect(manager.addedRoutes, isEmpty);
    });
  });

  group('disableSplitTunnel', () {
    test('removes only tracked routes', () async {
      final removedCalls = <String>[];
      mockChannel((call) async {
        if (call.method == 'addRoute') return true;
        if (call.method == 'getRoutes') return '10.0.0.0/8 via 10.0.0.1 dev eth0';
        if (call.method == 'removeRoute') {
          removedCalls.add((call.arguments as Map)['destinationCidr']);
          return true;
        }
        return null;
      });

      // Enable first.
      await manager.enableSplitTunnel(
        hospitalSubnets: ['10.0.0.0/8', '192.168.100.0/24'],
        hospitalGateway: '10.0.0.1',
        hospitalInterface: 'eth0',
      );

      // Now disable.
      final result = await manager.disableSplitTunnel();

      expect(result, true);
      expect(removedCalls.length, 2);
      expect(removedCalls, contains('10.0.0.0/8'));
      expect(removedCalls, contains('192.168.100.0/24'));
      expect(manager.addedRoutes, isEmpty);
    });

    test('returns true when no routes are tracked', () async {
      final result = await manager.disableSplitTunnel();
      expect(result, true);
    });

    test('returns false when removeRoute fails', () async {
      mockChannel((call) async {
        if (call.method == 'addRoute') return true;
        if (call.method == 'getRoutes') return '10.0.0.0/8 via 10.0.0.1 dev eth0';
        if (call.method == 'removeRoute') return false; // Always fails.
        return null;
      });

      await manager.enableSplitTunnel(
        hospitalSubnets: ['10.0.0.0/8'],
        hospitalGateway: '10.0.0.1',
        hospitalInterface: 'eth0',
      );

      final result = await manager.disableSplitTunnel();
      expect(result, false);
      // Routes are NOT cleared when removal fails.
      expect(manager.addedRoutes.length, 1);
    });

    test('clears tracked routes only when all removals succeed', () async {
      var removeCount = 0;
      mockChannel((call) async {
        if (call.method == 'addRoute') return true;
        if (call.method == 'getRoutes') return '10.0.0.0/8 via 10.0.0.1 dev eth0';
        if (call.method == 'removeRoute') {
          removeCount++;
          // Succeed for the first, fail for the second.
          return removeCount == 1;
        }
        return null;
      });

      await manager.enableSplitTunnel(
        hospitalSubnets: ['10.0.0.0/8', '192.168.100.0/24'],
        hospitalGateway: '10.0.0.1',
        hospitalInterface: 'eth0',
      );

      final result = await manager.disableSplitTunnel();
      expect(result, false);
      // Partial failure — routes should NOT be cleared.
      expect(manager.addedRoutes.isNotEmpty, true);
    });
  });

  // ──────────────────────────────────────────────────────────
  // getCurrentRoutes / listInterfaces
  // ──────────────────────────────────────────────────────────

  group('getCurrentRoutes', () {
    test('returns parsed routes from platform channel output', () async {
      mockChannel((call) async {
        if (call.method == 'getRoutes') {
          return '10.0.0.0/8 via 10.0.0.1 dev tun0\ndefault via 192.168.1.1 dev eth0';
        }
        return null;
      });

      final routes = await manager.getCurrentRoutes();
      expect(routes.length, 2);
      expect(routes[0].destinationCidr, '10.0.0.0/8');
    });

    test('returns empty list on PlatformException', () async {
      mockChannel((_) async => throw PlatformException(code: 'unknown'));

      final routes = await manager.getCurrentRoutes();
      expect(routes, isEmpty);
    });

    test('returns empty list when channel returns null', () async {
      mockChannel((_) async => null);

      final routes = await manager.getCurrentRoutes();
      expect(routes, isEmpty);
    });
  });

  group('listInterfaces', () {
    test('returns interface names from platform channel', () async {
      mockChannel((call) async {
        if (call.method == 'listInterfaces') {
          return ['eth0', 'tun0', 'lo'];
        }
        return null;
      });

      final interfaces = await manager.listInterfaces();
      expect(interfaces, ['eth0', 'tun0', 'lo']);
    });

    test('returns empty list on PlatformException', () async {
      mockChannel((_) async => throw PlatformException(code: 'unknown'));

      final interfaces = await manager.listInterfaces();
      expect(interfaces, isEmpty);
    });
  });

  // ──────────────────────────────────────────────────────────
  // State tracking
  // ──────────────────────────────────────────────────────────

  group('state tracking', () {
    test('addedRoutes is empty before enableSplitTunnel', () {
      expect(manager.addedRoutes, isEmpty);
    });

    test('enableSplitTunnel clears previous tracking before adding', () async {
      mockChannel((call) async {
        if (call.method == 'addRoute') return true;
        if (call.method == 'getRoutes') return '10.0.0.0/8 via 10.0.0.1 dev eth0';
        return null;
      });

      // First enable.
      await manager.enableSplitTunnel(
        hospitalSubnets: ['10.0.0.0/8'],
        hospitalGateway: '10.0.0.1',
        hospitalInterface: 'eth0',
      );
      expect(manager.addedRoutes.length, 1);

      // Second enable with different subnets — old tracking cleared.
      await manager.enableSplitTunnel(
        hospitalSubnets: ['172.16.0.0/12'],
        hospitalGateway: '10.0.0.1',
        hospitalInterface: 'eth0',
      );
      expect(manager.addedRoutes.length, 1);
      expect(manager.addedRoutes[0].destinationCidr, '172.16.0.0/12');
    });

    test('addedRoutes returns unmodifiable list', () {
      // Cast to dynamic to bypass the generic type guard and test that
      // the underlying list is unmodifiable.
      expect(
        () => (manager.addedRoutes as dynamic).add('garbage'),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
