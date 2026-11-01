import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:medlink_connect/core/injection.dart';
import 'package:medlink_connect/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const diagnosticsChannel =
      MethodChannel('com.medlinkconnect/network_diagnostics');
  const routeChannel = MethodChannel('com.medlinkconnect/route_manager');

  testWidgets('app boots with native plugins registered', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await configureDependencies();

    await tester.pumpWidget(const MedLinkConnectApp());
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('MedLink Connect'), findsOneWidget);
  });

  testWidgets('diagnostics plugin reaches a local TCP socket', (tester) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((socket) => socket.destroy());

    final latency = await diagnosticsChannel.invokeMethod<int>(
      'checkTcpPort',
      {'host': '127.0.0.1', 'port': server.port},
    );

    expect(latency, isA<int>());
    expect(latency, greaterThanOrEqualTo(0));
  });

  testWidgets('route plugin exposes read-only network information',
      (tester) async {
    final interfaces = await routeChannel.invokeMethod<List<dynamic>>(
      'listInterfaces',
    );
    final info = await routeChannel.invokeMethod<Map<dynamic, dynamic>>(
      'getPrimaryDefaultRouteInfo',
    );

    expect(interfaces, isNotNull);
    expect(interfaces, isNotEmpty);
    expect(info, isNotNull);
    expect(info, contains('interfaceName'));
  });
}
