import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlink_connect/core/exceptions.dart';
import 'package:medlink_connect/features/split_tunnel/default_route_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DefaultRouteManager routeManager;
  final log = <MethodCall>[];

  setUp(() {
    log.clear();
    routeManager = DefaultRouteManager();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.medlinkconnect/route_manager'),
      (MethodCall methodCall) async {
        log.add(methodCall);
        switch (methodCall.method) {
          case 'addRoute':
            return 'Route added OK';
          case 'removeRoute':
            return 'Route removed OK';
          case 'enableSplitTunnel':
            return 'Split tunnel enabled';
          case 'disableSplitTunnel':
            return 'Split tunnel disabled';
          case 'verifyRoutes':
            return <String>[];
          default:
            return null;
        }
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.medlinkconnect/route_manager'),
      null,
    );
  });

  test('addRoute validates arguments before calling MethodChannel', () async {
    expect(
      () => routeManager.addRoute(
        destinationCidr: 'invalid-cidr',
        gateway: '192.168.1.1',
        interfaceName: 'Wi-Fi',
      ),
      throwsA(isA<RouteConfigurationException>()),
    );
    expect(log.isEmpty, isTrue);

    expect(
      () => routeManager.addRoute(
        destinationCidr: '1234',
        gateway: '192.168.1.1',
        interfaceName: 'Wi-Fi',
      ),
      throwsA(isA<RouteConfigurationException>()),
    );
    expect(
      () => routeManager.addRoute(
        destinationCidr: '10.0.0.0/8',
        gateway: '999.1.1.1',
        interfaceName: 'Wi-Fi',
      ),
      throwsA(isA<RouteConfigurationException>()),
    );
    expect(log.isEmpty, isTrue);

    final res = await routeManager.addRoute(
      destinationCidr: '10.0.0.0/8',
      gateway: '192.168.1.1',
      interfaceName: 'Wi-Fi',
    );
    expect(res, equals('Route added OK'));
    expect(log.length, equals(1));
    expect(log.first.method, equals('addRoute'));
    expect(log.first.arguments['destinationCidr'], equals('10.0.0.0/8'));
  });

  test('removeRoute can clean an exact stale route', () async {
    final res = await routeManager.removeRoute(
      destinationCidr: '10.0.0.0/8',
      gateway: '192.168.1.1',
      interfaceName: 'Wi-Fi',
    );
    expect(res, equals('Route removed OK'));
    expect(log.first.method, equals('removeRoute'));
    expect(log.first.arguments['destinationCidr'], equals('10.0.0.0/8'));
    expect(log.first.arguments['gateway'], equals('192.168.1.1'));
    expect(log.first.arguments['interfaceName'], equals('Wi-Fi'));
  });

  test('removeRoute rejects incomplete or invalid exact cleanup data',
      () async {
    await expectLater(
      routeManager.removeRoute(
        destinationCidr: '10.0.0.0/8',
        gateway: '192.168.1.1',
      ),
      throwsA(isA<RouteConfigurationException>()),
    );
    await expectLater(
      routeManager.removeRoute(
        destinationCidr: '10.0.0.0/8',
        gateway: '999.1.1.1',
        interfaceName: 'Wi-Fi',
      ),
      throwsA(isA<RouteConfigurationException>()),
    );
    expect(log.isEmpty, isTrue);
  });

  test('enableSplitTunnel invokes channel correctly', () async {
    final res = await routeManager.enableSplitTunnel(
      hospitalSubnets: ['10.0.0.0/8'],
      gateway: '192.168.1.1',
      interfaceName: 'Wi-Fi',
    );
    expect(res, equals('Split tunnel enabled'));
    expect(log.first.method, equals('enableSplitTunnel'));
  });

  test('addRoute maps permission errors to a typed exception', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.medlinkconnect/route_manager'),
      (MethodCall methodCall) async {
        throw PlatformException(
          code: 'acceso_denegado',
          message: 'requiere administrador',
        );
      },
    );

    await expectLater(
      routeManager.addRoute(
        destinationCidr: '10.0.0.0/8',
        gateway: '192.168.1.1',
        interfaceName: 'Wi-Fi',
      ),
      throwsA(
        predicate(
          (error) =>
              error is MedLinkException &&
              error.type == MedLinkErrorType.permission,
        ),
      ),
    );
  });

  test('addRoute keeps non-permission errors as route failures', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.medlinkconnect/route_manager'),
      (MethodCall methodCall) async {
        throw PlatformException(code: 'ruta_invalida', message: 'sin gateway');
      },
    );

    await expectLater(
      routeManager.addRoute(
        destinationCidr: '10.0.0.0/8',
        gateway: '192.168.1.1',
        interfaceName: 'Wi-Fi',
      ),
      throwsA(
        predicate(
          (error) =>
              error is RouteConfigurationException &&
              error.type == MedLinkErrorType.route,
        ),
      ),
    );
  });
}
