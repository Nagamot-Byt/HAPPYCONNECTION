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

  test('addRoute falls back to a default message on null results', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.medlinkconnect/route_manager'),
      (MethodCall methodCall) async => null,
    );

    final res = await routeManager.addRoute(
      destinationCidr: '10.0.0.0/8',
      gateway: '192.168.1.1',
      interfaceName: 'Wi-Fi',
    );
    expect(res, equals('Route added.'));
  });

  test('enableSplitTunnel validates every argument before the channel',
      () async {
    await expectLater(
      routeManager.enableSplitTunnel(
        hospitalSubnets: ['no-es-cidr'],
        gateway: '192.168.1.1',
        interfaceName: 'Wi-Fi',
      ),
      throwsA(isA<RouteConfigurationException>()),
    );
    await expectLater(
      routeManager.enableSplitTunnel(
        hospitalSubnets: ['10.0.0.0/8'],
        gateway: '999.1.1.1',
        interfaceName: 'Wi-Fi',
      ),
      throwsA(isA<RouteConfigurationException>()),
    );
    await expectLater(
      routeManager.enableSplitTunnel(
        hospitalSubnets: ['10.0.0.0/8'],
        gateway: '192.168.1.1',
        interfaceName: '',
      ),
      throwsA(isA<RouteConfigurationException>()),
    );
    expect(log.isEmpty, isTrue);
  });

  test('removeRoute maps platform failures to typed exceptions', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.medlinkconnect/route_manager'),
      (MethodCall methodCall) async {
        throw PlatformException(code: 'privilege', message: 'sudo requerido');
      },
    );

    await expectLater(
      routeManager.removeRoute(
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

    await expectLater(
      routeManager.disableSplitTunnel(),
      throwsA(
        predicate(
          (error) =>
              error is MedLinkException &&
              error.type == MedLinkErrorType.permission,
        ),
      ),
    );
  });

  test('removeRoute falls back to a default message on null results', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.medlinkconnect/route_manager'),
      (MethodCall methodCall) async => null,
    );

    final res = await routeManager.removeRoute(
      destinationCidr: '10.0.0.0/8',
      gateway: '192.168.1.1',
      interfaceName: 'Wi-Fi',
    );
    expect(res, equals('Route removed.'));
  });

  test('disableSplitTunnel falls back to a default message on null', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.medlinkconnect/route_manager'),
      (MethodCall methodCall) async => null,
    );

    final res = await routeManager.disableSplitTunnel();
    expect(res, equals('Split tunnel disabled.'));
  });

  test('getRoutes returns the native output or an empty string', () async {
    final res = await routeManager.getRoutes();
    expect(res, isA<String>());

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.medlinkconnect/route_manager'),
      (MethodCall methodCall) async => null,
    );

    final empty = await routeManager.getRoutes();
    expect(empty, equals(''));
  });

  test('getPrimaryDefaultRouteInfo maps the native payload to strings',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.medlinkconnect/route_manager'),
      (MethodCall methodCall) async => <dynamic, dynamic>{
        'interfaceName': 'wlan0',
        'gateway': '192.168.5.1',
        'extra': null,
      },
    );

    final info = await routeManager.getPrimaryDefaultRouteInfo();
    expect(info['interfaceName'], equals('wlan0'));
    expect(info['gateway'], equals('192.168.5.1'));
    expect(info['extra'], equals(''));

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.medlinkconnect/route_manager'),
      (MethodCall methodCall) async => null,
    );

    final empty = await routeManager.getPrimaryDefaultRouteInfo();
    expect(empty, isEmpty);
  });

  test('listInterfaces returns the native list or an empty fallback', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.medlinkconnect/route_manager'),
      (MethodCall methodCall) async => <dynamic>['wlan0', 'eth0'],
    );

    final ifaces = await routeManager.listInterfaces();
    expect(ifaces, equals(['wlan0', 'eth0']));

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.medlinkconnect/route_manager'),
      (MethodCall methodCall) async => null,
    );

    final empty = await routeManager.listInterfaces();
    expect(empty, isEmpty);
  });

  test('listInterfaces maps platform failures to typed exceptions', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.medlinkconnect/route_manager'),
      (MethodCall methodCall) async {
        throw PlatformException(code: 'route_error', message: 'list failed');
      },
    );

    await expectLater(
      routeManager.listInterfaces(),
      throwsA(isA<RouteConfigurationException>()),
    );
    await expectLater(
      routeManager.getPrimaryDefaultRouteInfo(),
      throwsA(isA<RouteConfigurationException>()),
    );
  });

  test('verifyRoutes validates arguments before the channel', () async {
    await expectLater(
      routeManager.verifyRoutes(
        hospitalSubnets: ['bad cidr'],
        gateway: '192.168.1.1',
        interfaceName: 'Wi-Fi',
      ),
      throwsA(isA<RouteConfigurationException>()),
    );
    await expectLater(
      routeManager.verifyRoutes(
        hospitalSubnets: ['10.0.0.0/8'],
        gateway: '',
        interfaceName: 'Wi-Fi',
      ),
      throwsA(isA<RouteConfigurationException>()),
    );
    expect(log.isEmpty, isTrue);
  });

  test('verifyRoutes returns missing routes without retry when complete',
      () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.medlinkconnect/route_manager'),
      (MethodCall methodCall) async {
        calls++;
        return <String>[];
      },
    );

    final missing = await routeManager.verifyRoutes(
      hospitalSubnets: ['10.0.0.0/8'],
      gateway: '192.168.1.1',
      interfaceName: 'Wi-Fi',
    );
    expect(missing, isEmpty);
    expect(calls, equals(1));
  });

  test('verifyRoutes retries once when routes are still missing', () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.medlinkconnect/route_manager'),
      (MethodCall methodCall) async {
        calls++;
        return calls == 1
            ? <String>['10.0.0.0/8']
            : <String>['10.0.0.0/8', '172.16.0.0/12'];
      },
    );

    final missing = await routeManager.verifyRoutes(
      hospitalSubnets: ['10.0.0.0/8', '172.16.0.0/12'],
      gateway: '192.168.1.1',
      interfaceName: 'Wi-Fi',
    );
    expect(calls, equals(2));
    expect(missing, equals(['10.0.0.0/8', '172.16.0.0/12']));
  });

  test('verifyRoutes keeps the first report when the retry is null', () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.medlinkconnect/route_manager'),
      (MethodCall methodCall) async {
        calls++;
        return calls == 1 ? <String>['10.0.0.0/8'] : null;
      },
    );

    final missing = await routeManager.verifyRoutes(
      hospitalSubnets: ['10.0.0.0/8'],
      gateway: '192.168.1.1',
      interfaceName: 'Wi-Fi',
    );
    expect(calls, equals(2));
    expect(missing, equals(['10.0.0.0/8']));
  });

  test('verifyRoutes maps platform failures to typed exceptions', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.medlinkconnect/route_manager'),
      (MethodCall methodCall) async {
        throw PlatformException(
          code: 'route_error',
          message: 'verificacion fallida',
        );
      },
    );

    await expectLater(
      routeManager.verifyRoutes(
        hospitalSubnets: ['10.0.0.0/8'],
        gateway: '192.168.1.1',
        interfaceName: 'Wi-Fi',
      ),
      throwsA(isA<RouteConfigurationException>()),
    );
  });

  test('permission detection covers message based hints', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.medlinkconnect/route_manager'),
      (MethodCall methodCall) async {
        throw PlatformException(
          code: 'x',
          message: 'operacion con privilegio requerido',
        );
      },
    );

    await expectLater(
      routeManager.getRoutes(),
      throwsA(
        predicate(
          (error) =>
              error is MedLinkException &&
              error.type == MedLinkErrorType.permission,
        ),
      ),
    );
  });
}
