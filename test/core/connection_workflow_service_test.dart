import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:medlink_connect/core/connection_workflow_service.dart';
import 'package:medlink_connect/core/exceptions.dart';
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
    when(() => mockWifiManager.getCurrentConnectionInfo()).thenAnswer(
      (_) async => const WifiConnectionInfo(
        ssid: 'HUV_WIFI',
        interfaceName: 'Wi-Fi',
        gateway: '192.168.1.1',
      ),
    );
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
    when(() => mockRdpLauncher.preLaunch()).thenAnswer((_) async => true);
    when(() => mockRdpLauncher.launchRdp(
          host: '192.168.1.100',
          port: 3389,
          username: 'doctor',
          domain: 'HUV',
          profile: 'adaptive',
          measuredLatencyMs: 25,
        )).thenAnswer((_) async => 'RDP Launched');

    List<String>? cleanupSubnets;
    String? cleanupGateway;
    String? cleanupIface;
    final states = await workflowService.connect(
      subnets: ['10.0.0.0/8'],
      host: '192.168.1.100',
      user: 'doctor',
      domain: 'HUV',
      selectedWifi: 'HUV_WIFI',
      gateway: '192.168.1.1',
      iface: 'Wi-Fi',
      resolvedPort: 3389,
      onSplitTunnelEnabled: (subnets, gateway, iface) async {
        cleanupSubnets = subnets;
        cleanupGateway = gateway;
        cleanupIface = iface;
      },
    ).toList();

    expect(cleanupSubnets, ['10.0.0.0/8']);
    expect(cleanupGateway, '192.168.1.1');
    expect(cleanupIface, 'Wi-Fi');
    expect(states.first.step, ConnectionStep.diagnostics);
    expect(states.last.step, ConnectionStep.done);
    expect(states.last.isFinished, isTrue);
    expect(states.last.isError, isFalse);
  });

  test('Wi-Fi failure prevents route and RDP operations', () async {
    when(() => mockWifiManager.getCurrentConnectionInfo()).thenAnswer(
      (_) async => const WifiConnectionInfo(
        ssid: 'OtraRed',
        interfaceName: 'Wi-Fi',
        gateway: '192.168.1.1',
      ),
    );
    when(() => mockWifiManager.connect(ssid: 'HUV_WIFI', password: null))
        .thenThrow(const WifiConnectionException('contraseña inválida'));

    final states = await workflowService.connect(
      subnets: ['10.0.0.0/8'],
      host: '192.168.1.100',
      user: 'doctor',
      domain: 'HUV',
      selectedWifi: 'HUV_WIFI',
      gateway: '192.168.1.1',
      iface: 'Wi-Fi',
      resolvedPort: 3389,
    ).toList();

    expect(states.last.step, ConnectionStep.error);
    expect(states.last.isError, isTrue);
    verifyNever(() => mockRouteManager.enableSplitTunnel(
          hospitalSubnets: any(named: 'hospitalSubnets'),
          gateway: any(named: 'gateway'),
          interfaceName: any(named: 'interfaceName'),
        ));
  });

  test('Partial split-tunnel failure triggers cleanup', () async {
    when(() => mockRouteManager.enableSplitTunnel(
          hospitalSubnets: ['10.0.0.0/8'],
          gateway: '192.168.1.1',
          interfaceName: 'Wi-Fi',
        )).thenThrow(
      const RouteConfigurationException('falló la segunda ruta'),
    );
    when(() => mockRouteManager.disableSplitTunnel())
        .thenAnswer((_) async => 'Rolled back');

    final states = await workflowService.connect(
      subnets: ['10.0.0.0/8'],
      host: '192.168.1.100',
      user: '',
      domain: '',
      selectedWifi: '',
      gateway: '192.168.1.1',
      iface: 'Wi-Fi',
      resolvedPort: 3389,
    ).toList();

    expect(states.last.step, ConnectionStep.error);
    verify(() => mockRouteManager.disableSplitTunnel()).called(1);
  });

  test('iOS fallback marks the tunnel unavailable without a cleanup record',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    when(() => mockRouteManager.enableSplitTunnel(
          hospitalSubnets: ['10.0.0.0/8'],
          gateway: '192.168.1.1',
          interfaceName: 'Wi-Fi',
        )).thenThrow(
      const RouteConfigurationException('requiere NetworkExtension'),
    );
    when(() => mockRouteManager.disableSplitTunnel()).thenThrow(
      const RouteConfigurationException('sin rutas activas'),
    );
    when(() => mockNetworkDiagnostics.ping('192.168.1.100'))
        .thenAnswer((_) async => 20);
    when(() => mockNetworkDiagnostics.checkTcpPort('192.168.1.100', 3389))
        .thenAnswer((_) async => 25);
    when(() => mockRdpLauncher.isRdpClientAvailable())
        .thenAnswer((_) async => true);
    when(() => mockRdpLauncher.preLaunch()).thenAnswer((_) async => true);
    when(() => mockRdpLauncher.launchRdp(
          host: '192.168.1.100',
          port: 3389,
          username: 'doctor',
          domain: 'HUV',
          profile: 'adaptive',
          measuredLatencyMs: 25,
        )).thenAnswer((_) async => 'RDP Launched');

    var unavailable = false;
    var rolledBack = false;
    final states = await workflowService.connect(
      subnets: ['10.0.0.0/8'],
      host: '192.168.1.100',
      user: 'doctor',
      domain: 'HUV',
      selectedWifi: '',
      gateway: '192.168.1.1',
      iface: 'Wi-Fi',
      resolvedPort: 3389,
      onSplitTunnelUnavailable: () async {
        unavailable = true;
      },
      onSplitTunnelRolledBack: () async {
        rolledBack = true;
      },
    ).toList();

    expect(unavailable, isTrue);
    expect(rolledBack, isFalse);
    expect(
      states.any(
          (state) => state.step == ConnectionStep.preLaunch && state.isError),
      isTrue,
    );
    expect(states.last.step, ConnectionStep.done);
  });

  test('fallback keeps the cleanup record when enable never succeeded',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    when(() => mockRouteManager.enableSplitTunnel(
          hospitalSubnets: ['10.0.0.0/8'],
          gateway: '192.168.1.1',
          interfaceName: 'Wi-Fi',
        )).thenThrow(
      const RouteConfigurationException('requiere NetworkExtension'),
    );
    when(() => mockRouteManager.disableSplitTunnel())
        .thenAnswer((_) async => 'Sin rutas activas');
    when(() => mockNetworkDiagnostics.ping('192.168.1.100'))
        .thenAnswer((_) async => 20);
    when(() => mockNetworkDiagnostics.checkTcpPort('192.168.1.100', 3389))
        .thenAnswer((_) async => 25);
    when(() => mockRdpLauncher.isRdpClientAvailable())
        .thenAnswer((_) async => true);
    when(() => mockRdpLauncher.preLaunch()).thenAnswer((_) async => true);
    when(() => mockRdpLauncher.launchRdp(
          host: '192.168.1.100',
          port: 3389,
          username: 'doctor',
          domain: 'HUV',
          profile: 'adaptive',
          measuredLatencyMs: 25,
        )).thenAnswer((_) async => 'RDP Launched');

    var unavailable = false;
    var rolledBack = false;
    final states = await workflowService.connect(
      subnets: ['10.0.0.0/8'],
      host: '192.168.1.100',
      user: 'doctor',
      domain: 'HUV',
      selectedWifi: '',
      gateway: '192.168.1.1',
      iface: 'Wi-Fi',
      resolvedPort: 3389,
      onSplitTunnelUnavailable: () async {
        unavailable = true;
      },
      onSplitTunnelRolledBack: () async {
        rolledBack = true;
      },
    ).toList();

    expect(unavailable, isTrue);
    expect(rolledBack, isFalse);
    verify(() => mockRouteManager.disableSplitTunnel()).called(1);
    expect(states.last.step, ConnectionStep.done);
  });

  test('server selection runs after the split tunnel and updates the target',
      () async {
    final order = <String>[];
    when(() => mockRouteManager.enableSplitTunnel(
          hospitalSubnets: ['10.0.0.0/8'],
          gateway: '192.168.1.1',
          interfaceName: 'Wi-Fi',
        )).thenAnswer((_) async {
      order.add('enable');
      return 'Routes added';
    });
    when(() => mockRouteManager.verifyRoutes(
          hospitalSubnets: ['10.0.0.0/8'],
          gateway: '192.168.1.1',
          interfaceName: 'Wi-Fi',
        )).thenAnswer((_) async => []);
    when(() => mockNetworkDiagnostics.ping('10.1.2.3')).thenAnswer((_) async {
      order.add('ping');
      return 15;
    });
    when(() => mockNetworkDiagnostics.checkTcpPort('10.1.2.3', 3390))
        .thenAnswer((_) async => 20);
    when(() => mockRdpLauncher.isRdpClientAvailable())
        .thenAnswer((_) async => true);
    when(() => mockRdpLauncher.preLaunch()).thenAnswer((_) async => true);
    when(() => mockRdpLauncher.launchRdp(
          host: '10.1.2.3',
          port: 3390,
          username: null,
          domain: null,
          profile: 'adaptive',
          measuredLatencyMs: 20,
        )).thenAnswer((_) async => 'RDP Launched');

    final states = await workflowService.connect(
      subnets: ['10.0.0.0/8'],
      host: '192.168.1.100',
      user: '',
      domain: '',
      selectedWifi: '',
      gateway: '192.168.1.1',
      iface: 'Wi-Fi',
      resolvedPort: 3389,
      onSelectServer: () async {
        order.add('select');
        return (host: '10.1.2.3', port: 3390);
      },
    ).toList();

    expect(order, ['enable', 'select', 'ping']);
    verifyNever(() => mockNetworkDiagnostics.ping('192.168.1.100'));
    verify(() => mockRdpLauncher.launchRdp(
          host: '10.1.2.3',
          port: 3390,
          username: null,
          domain: null,
          profile: 'adaptive',
          measuredLatencyMs: 20,
        )).called(1);
    expect(states.last.step, ConnectionStep.done);
  });

  test('Missing Wi-Fi plugin falls back to the current network', () async {
    when(() => mockWifiManager.getCurrentConnectionInfo())
        .thenThrow(MissingPluginException('no wifi'));
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
    when(() => mockRdpLauncher.preLaunch()).thenAnswer((_) async => true);
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
    ).toList();

    expect(states.last.step, ConnectionStep.done);
    verifyNever(() => mockWifiManager.connect(
          ssid: any(named: 'ssid'),
          password: any(named: 'password'),
        ));
  });

  test('TCP failure rolls back the split tunnel', () async {
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
        .thenAnswer((_) async => null);
    when(() => mockRouteManager.disableSplitTunnel())
        .thenAnswer((_) async => 'Rolled back');

    var rolledBack = false;
    final states = await workflowService.connect(
      subnets: ['10.0.0.0/8'],
      host: '192.168.1.100',
      user: '',
      domain: '',
      selectedWifi: '',
      gateway: '192.168.1.1',
      iface: 'Wi-Fi',
      resolvedPort: 3389,
      onSplitTunnelRolledBack: () async {
        rolledBack = true;
      },
    ).toList();

    expect(states.last.step, ConnectionStep.error);
    expect(states.last.isError, isTrue);
    expect(rolledBack, isTrue);
    verify(() => mockRouteManager.disableSplitTunnel()).called(1);
  });

  test('Rollback callback keeps the cleanup record when disable fails',
      () async {
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
        .thenAnswer((_) async => null);
    when(() => mockRouteManager.disableSplitTunnel())
        .thenThrow(const RouteConfigurationException('sin permisos'));

    var rolledBack = false;
    final states = await workflowService.connect(
      subnets: ['10.0.0.0/8'],
      host: '192.168.1.100',
      user: '',
      domain: '',
      selectedWifi: '',
      gateway: '192.168.1.1',
      iface: 'Wi-Fi',
      resolvedPort: 3389,
      onSplitTunnelRolledBack: () async {
        rolledBack = true;
      },
    ).toList();

    expect(states.last.step, ConnectionStep.error);
    expect(rolledBack, isFalse);
    verify(() => mockRouteManager.disableSplitTunnel()).called(1);
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
    ).toList();

    expect(states.last.step, ConnectionStep.error);
    expect(states.last.isError, isTrue);
  });
}
