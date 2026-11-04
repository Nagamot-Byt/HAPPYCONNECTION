import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:medlink_connect/core/injection.dart';
import 'package:medlink_connect/core/wifi_manager.dart';
import 'package:medlink_connect/features/ui/home_controller.dart';
import 'package:medlink_connect/features/ui/widgets/network_diagnostics_view.dart';
import 'package:medlink_connect/main.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _expectWifiUi = bool.fromEnvironment('EXPECT_WIFI_UI');

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

  testWidgets(
    'wifi dropdown lists scanned networks and connects',
    skip: !_expectWifiUi,
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      if (!getIt.isRegistered<WifiManager>()) {
        await configureDependencies();
      }

      await tester.pumpWidget(const MedLinkConnectApp());
      await tester.pump(const Duration(seconds: 1));

      final diagnosticsFinder = find.byType(NetworkDiagnosticsView);
      expect(diagnosticsFinder, findsOneWidget);
      final controller = Provider.of<HomeController>(
        tester.element(diagnosticsFinder),
        listen: false,
      );

      final scanDeadline = DateTime.now().add(const Duration(seconds: 30));
      while (controller.wifiNetworks.isEmpty &&
          controller.wifiScanError == null &&
          DateTime.now().isBefore(scanDeadline)) {
        await tester.pump(const Duration(milliseconds: 500));
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      expect(controller.wifiScanError, isNull);
      expect(controller.wifiNetworks, isNotEmpty);
      final dropdownFinder = find.byType(DropdownButton<String>).first;
      final dropdown = tester.widget<DropdownButton<String>>(dropdownFinder);
      expect(dropdown.items, isNotNull);
      expect(dropdown.items!.length, controller.wifiNetworks.length + 1);
      for (final ssid in controller.wifiNetworks) {
        expect(
          dropdown.items!.any((item) => item.value == ssid),
          isTrue,
          reason: 'Falta la red $ssid en el desplegable',
        );
      }

      final current = await controller.wifiManager!.getCurrentConnectionInfo();
      expect(current.ssid, isNotEmpty);
      controller.selectedWifiSsid = current.ssid;
      controller.manualWifiCtrl.text = current.ssid;
      await tester.pump();

      final connectButton = find.byIcon(Icons.wifi);
      expect(connectButton, findsOneWidget);
      await tester.ensureVisible(connectButton);
      await tester.tap(connectButton);
      await tester.pump();

      final connectDeadline = DateTime.now().add(const Duration(seconds: 60));
      while (controller.busy && DateTime.now().isBefore(connectDeadline)) {
        await tester.pump(const Duration(milliseconds: 500));
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }

      expect(controller.busy, isFalse);
      expect(controller.guidanceIsError, isFalse);
      expect(controller.currentWifiSsid, current.ssid);
      expect(controller.gatewayCtrl.text.trim(), isNotEmpty);
      expect(controller.ifaceCtrl.text.trim(), isNotEmpty);
    },
  );
}
