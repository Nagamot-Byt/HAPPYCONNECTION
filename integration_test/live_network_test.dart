import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _rdpHost = String.fromEnvironment('RDP_TEST_HOST');
const _rdpPort = int.fromEnvironment('RDP_TEST_PORT', defaultValue: 3389);
const _expectWifi = bool.fromEnvironment('EXPECT_WIFI');
const _routeCidr = String.fromEnvironment('ROUTE_TEST_CIDR');
const _routeGateway = String.fromEnvironment('ROUTE_TEST_GATEWAY');
const _routeInterface = String.fromEnvironment('ROUTE_TEST_INTERFACE');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const diagnosticsChannel =
      MethodChannel('com.medlinkconnect/network_diagnostics');
  const wifiChannel = MethodChannel('com.medlinkconnect/wifi_manager');
  const routeChannel = MethodChannel('com.medlinkconnect/route_manager');

  testWidgets(
    'live RDP target accepts TCP connections',
    skip: _rdpHost.isEmpty,
    (tester) async {
      final latency = await diagnosticsChannel.invokeMethod<int>(
        'checkTcpPort',
        {'host': _rdpHost, 'port': _rdpPort},
      );

      expect(latency, isA<int>());
      expect(latency, greaterThanOrEqualTo(0));
    },
  );

  testWidgets(
    'live Wi-Fi reports an active hospital network',
    skip: !_expectWifi,
    (tester) async {
      final info = await wifiChannel.invokeMapMethod<String, dynamic>(
        'getCurrentConnectionInfo',
      );

      expect(info, isNotNull);
      expect((info?['ssid'] as String?)?.trim(), isNotEmpty);
    },
  );

  testWidgets(
    'live privileged route add and remove succeeds',
    skip:
        _routeCidr.isEmpty || _routeGateway.isEmpty || _routeInterface.isEmpty,
    (tester) async {
      await routeChannel.invokeMethod<String>('addRoute', {
        'destinationCidr': _routeCidr,
        'gateway': _routeGateway,
        'interfaceName': _routeInterface,
      });
      addTearDown(() async {
        await routeChannel.invokeMethod<String>('removeRoute', {
          'destinationCidr': _routeCidr,
          'gateway': _routeGateway,
          'interfaceName': _routeInterface,
        });
      });

      final missing = await routeChannel.invokeMethod<List<dynamic>>(
        'verifyRoutes',
        {
          'hospitalSubnets': [_routeCidr],
          'gateway': _routeGateway,
          'interfaceName': _routeInterface,
        },
      );

      expect(missing, isEmpty);
    },
  );
}
