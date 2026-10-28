import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:medlink_connect/core/connection_workflow_service.dart';
import 'package:medlink_connect/core/route_manager.dart';
import 'package:medlink_connect/core/network_diagnostics.dart';
import 'package:medlink_connect/core/rdp_launcher.dart';
import 'package:medlink_connect/core/wifi_manager.dart';
import 'package:medlink_connect/features/ui/home_controller.dart'
    show ConnectionStep;

class MockRouteManager extends Mock implements RouteManager {}

class MockNetworkDiagnostics extends Mock implements NetworkDiagnostics {}

class MockRdpLauncher extends Mock implements RdpLauncher {}

class MockWifiManager extends Mock implements WifiManager {}

void main() {
  late MockRouteManager mockRouteManager;
  late MockNetworkDiagnostics mockNetworkDiagnostics;
  late MockRdpLauncher mockRdpLauncher;
  late MockWifiManager mockWifiManager;
  late ConnectionWorkflowService workflowService;

  setUp(() {
    mockRouteManager = MockRouteManager();
    mockNetworkDiagnostics = MockNetworkDiagnostics();
    mockRdpLauncher = MockRdpLauncher();
    mockWifiManager = MockWifiManager();

    workflowService = ConnectionWorkflowService(
      mockRouteManager,
      mockNetworkDiagnostics,
      mockRdpLauncher,
      wifiManager: mockWifiManager,
    );
  });

  test('Happy path connection flow emits expected steps', () async {
    when(() => mockWifiManager.connect(ssid: 'HUV_WIFI', password: null))
        .thenAnswer((_) async => 'success');
    when(() => mockRouteManager.enableSplitTunnel(
          hospitalSubnets: ['10.0.0.0/8'],
          gateway: '192.168.1.1',
          interfaceName: 'Wi-Fi',
        )).thenAnswer((_) async => 'Routes added');
    when(() => mockRouteManager.verifyRoutes(
          hospitalSubnets: ['10.0.0.0/8'],
          gateway: '192.168.1.1',
          interfaceName: 'Wi-Fi',
        )).thenAnswer((_) async => []);
    when(() => mockNetworkDiagnostics.ping('192.168.1.100'))
        .thenAnswer((_) async => 20);
    when(() => mockNetworkDiagnostics.checkTcpPort('192.168.1.100', 3389))
        .thenAnswer((_) async => 25);
    when(() => mockRdpLauncher.isRdpClientAvailable())
        .thenAnswer((_) async => true);
    when(() => mockRdpLauncher.launchRdp(
          host: '192.168.1.100',
          port: 3389,
          username: 'doctor',
          domain: 'HUV',
          profile: 'adaptive',
          measuredLatencyMs: 25,
        )).thenAnswer((_) async => 'RDP Launched');

    final states = await workflowService.connect(
      subnets: ['10.0.0.0/8'],
      host: '192.168.1.100',
      user: 'doctor',
      domain: 'HUV',
      selectedWifi: 'HUV_WIFI',
      gateway: '192.168.1.1',
      iface: 'Wi-Fi',
      resolvedPort: 3389,
      preferMostStableServer: false,
    ).toList();

    expect(states.first.step, ConnectionStep.diagnostics);
    expect(states.last.step, ConnectionStep.done);
    expect(states.last.isFinished, isTrue);
    expect(states.last.isError, isFalse);
  });

  test('Sanitization failure emits error step immediately', () async {
    final states = await workflowService.connect(
      subnets: ['10.0.0.0/8; rm -rf /'],
      host: '192.168.1.100',
      user: '',
      domain: '',
      selectedWifi: '',
      gateway: '192.168.1.1',
      iface: 'Wi-Fi',
      resolvedPort: 3389,
      preferMostStableServer: false,
    ).toList();

    expect(states.last.step, ConnectionStep.error);
    expect(states.last.isError, isTrue);
  });
}
