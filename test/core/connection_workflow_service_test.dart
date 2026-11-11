import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations_en.dart';
import 'package:flutter_gen/gen_l10n/app_localizations_es.dart';
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

void _stubSuccessfulRdp(
  MockNetworkDiagnostics diagnostics,
  MockRdpLauncher launcher, {
  String host = '192.168.1.100',
  int port = 3389,
  int latency = 25,
}) {
  when(() => diagnostics.ping(host)).thenAnswer((_) async => 20);
  when(() => diagnostics.checkTcpPort(host, port))
      .thenAnswer((_) async => latency);
  when(() => launcher.isRdpClientAvailable()).thenAnswer((_) async => true);
  when(() => launcher.preLaunch()).thenAnswer((_) async => true);
  when(() => launcher.launchRdp(
        host: host,
        port: port,
        username: null,
        domain: null,
        profile: 'adaptive',
        measuredLatencyMs: latency,
      )).thenAnswer((_) async => 'RDP Launched');
}

void _stubRoutes(
  MockRouteManager manager, {
  String gateway = '192.168.1.1',
  String iface = 'Wi-Fi',
}) {
  when(() => manager.enableSplitTunnel(
        hospitalSubnets: ['10.0.0.0/8'],
        gateway: gateway,
        interfaceName: iface,
      )).thenAnswer((_) async => 'Rutas agregadas');
  when(() => manager.verifyRoutes(
        hospitalSubnets: ['10.0.0.0/8'],
        gateway: gateway,
        interfaceName: iface,
      )).thenAnswer((_) async => []);
}

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
    )..configureLocalizations(AppLocalizationsEs());
  });

  test('workflow logs follow the configured locale', () async {
    workflowService.configureLocalizations(AppLocalizationsEn());

    final state = await workflowService.connect(
      subnets: const [],
      host: '',
      user: '',
      domain: '',
      selectedWifi: '',
      gateway: '',
      iface: '',
      resolvedPort: 3389,
    ).first;

    expect(state.logMessage, 'Starting full connection flow…');
  });

  test('Happy path connection flow emits expected steps', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
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
    var verifyCalls = 0;
    when(() => mockRouteManager.verifyRoutes(
          hospitalSubnets: ['10.0.0.0/8'],
          gateway: '192.168.1.1',
          interfaceName: 'Wi-Fi',
        )).thenAnswer((_) async {
      verifyCalls++;
      return verifyCalls == 1 ? ['10.0.0.0/8'] : <String>[];
    });
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

  test('desktop pre-check records only routes that were missing', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    when(() => mockRouteManager.enableSplitTunnel(
          hospitalSubnets: ['10.0.0.0/8', '172.16.0.0/12'],
          gateway: '192.168.1.1',
          interfaceName: 'Wi-Fi',
        )).thenAnswer((_) async => 'Routes added');
    when(() => mockRouteManager.verifyRoutes(
          hospitalSubnets: ['10.0.0.0/8'],
          gateway: '192.168.1.1',
          interfaceName: 'Wi-Fi',
        )).thenAnswer((_) async => const <String>[]);
    when(() => mockRouteManager.verifyRoutes(
          hospitalSubnets: ['172.16.0.0/12'],
          gateway: '192.168.1.1',
          interfaceName: 'Wi-Fi',
        )).thenAnswer((_) async => ['172.16.0.0/12']);
    when(() => mockRouteManager.verifyRoutes(
          hospitalSubnets: ['10.0.0.0/8', '172.16.0.0/12'],
          gateway: '192.168.1.1',
          interfaceName: 'Wi-Fi',
        )).thenAnswer((_) async => const <String>[]);
    _stubSuccessfulRdp(mockNetworkDiagnostics, mockRdpLauncher);

    List<String>? cleanupSubnets;
    final states = await workflowService.connect(
      subnets: ['10.0.0.0/8', '172.16.0.0/12'],
      host: '192.168.1.100',
      user: '',
      domain: '',
      selectedWifi: '',
      gateway: '192.168.1.1',
      iface: 'Wi-Fi',
      resolvedPort: 3389,
      onSplitTunnelEnabled: (subnets, gateway, iface) async {
        cleanupSubnets = subnets;
      },
    ).toList();

    expect(cleanupSubnets, ['172.16.0.0/12']);
    expect(states.last.step, ConnectionStep.done);
  });

  test('Wi-Fi failure prevents route and RDP operations', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
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

  test('Wi-Fi connection can start without a gateway or interface', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    when(() => mockWifiManager.getCurrentConnectionInfo()).thenAnswer(
      (_) async => const WifiConnectionInfo(
        ssid: '',
        interfaceName: '',
        gateway: '',
      ),
    );
    when(() => mockWifiManager.connect(ssid: 'HUV_WIFI', password: null))
        .thenThrow(const WifiConnectionException('sin credenciales'));

    final states = await workflowService.connect(
      subnets: ['10.0.0.0/8'],
      host: '192.168.1.100',
      user: '',
      domain: '',
      selectedWifi: 'HUV_WIFI',
      gateway: '',
      iface: '',
      resolvedPort: 3389,
    ).toList();

    verify(() => mockWifiManager.connect(ssid: 'HUV_WIFI', password: null))
        .called(1);
    expect(states.last.step, ConnectionStep.error);
    expect(states.last.errorType, MedLinkErrorType.wifi);
    verifyNever(() => mockRouteManager.enableSplitTunnel(
          hospitalSubnets: any(named: 'hospitalSubnets'),
          gateway: any(named: 'gateway'),
          interfaceName: any(named: 'interfaceName'),
        ));
  });

  test('SSIDs with trailing spaces are passed through unchanged', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    when(() => mockWifiManager.getCurrentConnectionInfo()).thenAnswer(
      (_) async => const WifiConnectionInfo(
        ssid: '',
        interfaceName: '',
        gateway: '',
      ),
    );
    when(() => mockWifiManager.connect(ssid: 'SAN FERNANDO ', password: null))
        .thenThrow(const WifiConnectionException('sin credenciales'));

    final states = await workflowService.connect(
      subnets: ['10.0.0.0/8'],
      host: '192.168.1.100',
      user: '',
      domain: '',
      selectedWifi: 'SAN FERNANDO ',
      gateway: '',
      iface: '',
      resolvedPort: 3389,
    ).toList();

    verify(() => mockWifiManager.connect(ssid: 'SAN FERNANDO ', password: null))
        .called(1);
    expect(states.last.errorType, MedLinkErrorType.wifi);
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

  test('Android permission error falls back to RDP without split tunnel',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    when(() => mockRouteManager.enableSplitTunnel(
          hospitalSubnets: ['10.0.0.0/8'],
          gateway: '192.168.1.1',
          interfaceName: 'Wi-Fi',
        )).thenThrow(
      const PrivilegeRequiredException('se requiere ROOT (su)'),
    );
    when(() => mockRouteManager.disableSplitTunnel()).thenThrow(
      const PrivilegeRequiredException('Requiere sudo.'),
    );
    _stubSuccessfulRdp(mockNetworkDiagnostics, mockRdpLauncher);

    var unavailable = false;
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
      onSplitTunnelUnavailable: () async {
        unavailable = true;
      },
      onSplitTunnelRolledBack: () async {
        rolledBack = true;
      },
    ).toList();

    expect(unavailable, isTrue);
    expect(rolledBack, isFalse);
    expect(states.last.step, ConnectionStep.done);
    expect(states.last.isError, isFalse);
  });

  test('privilege errors still abort on desktop platforms', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    when(() => mockRouteManager.enableSplitTunnel(
          hospitalSubnets: ['10.0.0.0/8'],
          gateway: '192.168.1.1',
          interfaceName: 'Wi-Fi',
        )).thenThrow(
      const PrivilegeRequiredException('se requiere Administrador'),
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
    expect(states.last.errorType, MedLinkErrorType.permission);
    verifyNever(() => mockRdpLauncher.launchRdp(
          host: any(named: 'host'),
          port: any(named: 'port'),
          username: any(named: 'username'),
          domain: any(named: 'domain'),
          useWebFeed: any(named: 'useWebFeed'),
          profile: any(named: 'profile'),
          measuredLatencyMs: any(named: 'measuredLatencyMs'),
        ));
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

  test('server selection runs before the split tunnel and updates the target',
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

    expect(order, ['select', 'enable', 'ping']);
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

  test('derives /32 routes from the RDP host when subnets are empty', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    workflowService.hostCidrResolver =
        (host) async => host == '192.168.1.100' ? ['192.168.1.100/32'] : [];

    when(() => mockRouteManager.verifyRoutes(
          hospitalSubnets: ['192.168.1.100/32'],
          gateway: '192.168.1.1',
          interfaceName: 'Wi-Fi',
        )).thenAnswer((_) async => <String>[]);
    when(() => mockRouteManager.enableSplitTunnel(
          hospitalSubnets: ['192.168.1.100/32'],
          gateway: '192.168.1.1',
          interfaceName: 'Wi-Fi',
        )).thenAnswer((_) async => 'Routes added');
    _stubSuccessfulRdp(mockNetworkDiagnostics, mockRdpLauncher);

    final states = await workflowService
        .connect(
          host: '192.168.1.100',
          user: '',
          domain: '',
          selectedWifi: '',
          gateway: '192.168.1.1',
          iface: 'Wi-Fi',
          resolvedPort: 3389,
        )
        .toList();

    verify(() => mockRouteManager.enableSplitTunnel(
          hospitalSubnets: ['192.168.1.100/32'],
          gateway: '192.168.1.1',
          interfaceName: 'Wi-Fi',
        )).called(1);
    expect(
      states.map((state) => state.logMessage),
      contains(contains('rutas /32')),
    );
    expect(states.last.step, ConnectionStep.done);
  });

  test('Missing Wi-Fi plugin falls back to the current network', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
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

  test('refreshes gateway and interface after connecting to another Wi-Fi',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    var infoCalls = 0;
    when(() => mockWifiManager.getCurrentConnectionInfo())
        .thenAnswer((_) async {
      infoCalls++;
      if (infoCalls == 1) {
        return const WifiConnectionInfo(
          ssid: 'OtraRed',
          interfaceName: 'wlan0',
          gateway: '192.168.1.1',
        );
      }
      return const WifiConnectionInfo(
        ssid: 'HUV_WIFI',
        interfaceName: 'wlan0',
        gateway: '10.0.0.1',
      );
    });
    when(() => mockWifiManager.connect(ssid: 'HUV_WIFI', password: null))
        .thenAnswer((_) async => 'ok');
    when(() => mockRouteManager.enableSplitTunnel(
          hospitalSubnets: ['10.0.0.0/8'],
          gateway: '10.0.0.1',
          interfaceName: 'wlan0',
        )).thenAnswer((_) async => 'Routes added');
    when(() => mockRouteManager.verifyRoutes(
          hospitalSubnets: ['10.0.0.0/8'],
          gateway: '10.0.0.1',
          interfaceName: 'wlan0',
        )).thenAnswer((_) async => []);
    _stubSuccessfulRdp(mockNetworkDiagnostics, mockRdpLauncher);

    final states = await workflowService.connect(
      subnets: ['10.0.0.0/8'],
      host: '192.168.1.100',
      user: '',
      domain: '',
      selectedWifi: 'HUV_WIFI',
      gateway: '192.168.1.1',
      iface: 'wlan0',
      resolvedPort: 3389,
    ).toList();

    verify(() => mockRouteManager.enableSplitTunnel(
          hospitalSubnets: ['10.0.0.0/8'],
          gateway: '10.0.0.1',
          interfaceName: 'wlan0',
        )).called(1);
    expect(states.last.step, ConnectionStep.done);
  });

  test('ignores the default route from a non Wi-Fi interface', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    when(() => mockWifiManager.getCurrentConnectionInfo()).thenAnswer(
      (_) async => const WifiConnectionInfo(
        ssid: 'HUV_WIFI',
        interfaceName: 'wlan0',
        gateway: '',
      ),
    );
    when(() => mockRouteManager.getPrimaryDefaultRouteInfo()).thenAnswer(
      (_) async => {'gateway': '192.168.1.1', 'interfaceName': 'eth0'},
    );

    final states = await workflowService.connect(
      subnets: ['10.0.0.0/8'],
      host: '192.168.1.100',
      user: '',
      domain: '',
      selectedWifi: 'HUV_WIFI',
      gateway: '',
      iface: '',
      resolvedPort: 3389,
    ).toList();

    expect(states.last.step, ConnectionStep.error);
    expect(states.last.errorType, MedLinkErrorType.route);
    verifyNever(() => mockRouteManager.enableSplitTunnel(
          hospitalSubnets: any(named: 'hospitalSubnets'),
          gateway: any(named: 'gateway'),
          interfaceName: any(named: 'interfaceName'),
        ));
  });

  test('Apple platforms continue without gateway or interface', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    when(() => mockWifiManager.getCurrentConnectionInfo()).thenAnswer(
      (_) async => const WifiConnectionInfo(
        ssid: 'HUV_WIFI',
        interfaceName: '',
        gateway: '',
      ),
    );
    when(() => mockRouteManager.enableSplitTunnel(
          hospitalSubnets: ['10.0.0.0/8'],
          gateway: '',
          interfaceName: '',
        )).thenThrow(
      const RouteConfigurationException('requiere NetworkExtension'),
    );
    when(() => mockRouteManager.disableSplitTunnel())
        .thenAnswer((_) async => 'Sin rutas activas');
    _stubSuccessfulRdp(mockNetworkDiagnostics, mockRdpLauncher);

    final states = await workflowService.connect(
      subnets: ['10.0.0.0/8'],
      host: '192.168.1.100',
      user: '',
      domain: '',
      selectedWifi: 'HUV_WIFI',
      gateway: '',
      iface: '',
      resolvedPort: 3389,
    ).toList();

    expect(states.last.step, ConnectionStep.done);
    verify(() => mockRouteManager.enableSplitTunnel(
          hospitalSubnets: ['10.0.0.0/8'],
          gateway: '',
          interfaceName: '',
        )).called(1);
  });

  test('Apple and Android continue without subnets, gateway or Wi-Fi',
      () async {
    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      _stubSuccessfulRdp(mockNetworkDiagnostics, mockRdpLauncher);

      final states = await workflowService.connect(
        subnets: const [],
        host: '192.168.1.100',
        user: '',
        domain: '',
        selectedWifi: 'HUV_WIFI',
        gateway: '',
        iface: '',
        resolvedPort: 3389,
      ).toList();

      expect(states.last.step, ConnectionStep.done, reason: '$platform');
      expect(
        states.map((state) => state.logMessage),
        contains(AppLocalizationsEs().logWorkflowNoSubnets),
      );
      verifyNever(() => mockRouteManager.enableSplitTunnel(
            hospitalSubnets: any(named: 'hospitalSubnets'),
            gateway: any(named: 'gateway'),
            interfaceName: any(named: 'interfaceName'),
          ));
      verifyNever(() => mockWifiManager.getCurrentConnectionInfo());
      verifyNever(() => mockWifiManager.connect(
            ssid: any(named: 'ssid'),
            password: any(named: 'password'),
          ));
    }
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

  test('connecting before localizations are configured fails fast', () async {
    final unconfigured = ConnectionWorkflowService(
      mockRouteManager,
      mockNetworkDiagnostics,
      mockRdpLauncher,
    );

    await expectLater(
      unconfigured.connect(
        subnets: const [],
        host: '192.168.1.100',
        user: '',
        domain: '',
        selectedWifi: '',
        gateway: '',
        iface: '',
        resolvedPort: 3389,
      ),
      emitsError(isA<StateError>()),
    );
  });

  test('Wi-Fi password is forwarded when joining a new network', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    var infoCalls = 0;
    when(() => mockWifiManager.getCurrentConnectionInfo())
        .thenAnswer((_) async {
      infoCalls++;
      if (infoCalls == 1) {
        return const WifiConnectionInfo(
          ssid: 'OtraRed',
          interfaceName: 'Wi-Fi',
          gateway: '192.168.1.1',
        );
      }
      return const WifiConnectionInfo(
        ssid: 'HUV_WIFI',
        interfaceName: 'wlan0',
        gateway: '192.168.5.1',
      );
    });
    when(() => mockWifiManager.connect(ssid: 'HUV_WIFI', password: 'secreto'))
        .thenAnswer((_) async => 'aceptada');
    _stubRoutes(mockRouteManager, gateway: '192.168.5.1', iface: 'wlan0');
    _stubSuccessfulRdp(mockNetworkDiagnostics, mockRdpLauncher);

    final states = await workflowService.connect(
      subnets: ['10.0.0.0/8'],
      host: '192.168.1.100',
      user: '',
      domain: '',
      selectedWifi: 'HUV_WIFI',
      gateway: '',
      iface: '',
      resolvedPort: 3389,
      wifiPassword: 'secreto',
    ).toList();

    verify(() => mockWifiManager.connect(ssid: 'HUV_WIFI', password: 'secreto'))
        .called(1);
    expect(states.last.step, ConnectionStep.done);
  });

  test('Wi-Fi that never confirms reports the system response', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    when(() => mockWifiManager.getCurrentConnectionInfo()).thenAnswer(
      (_) async => const WifiConnectionInfo(
        ssid: 'OtraRed',
        interfaceName: 'Wi-Fi',
        gateway: '192.168.1.1',
      ),
    );
    when(() => mockWifiManager.connect(ssid: 'HUV_WIFI', password: null))
        .thenAnswer((_) async => 'aceptada por NetworkManager');

    fakeAsync((async) {
      final states = <WorkflowState>[];
      final subscription = workflowService.connect(
        subnets: ['10.0.0.0/8'],
        host: '192.168.1.100',
        user: '',
        domain: '',
        selectedWifi: 'HUV_WIFI',
        gateway: '',
        iface: '',
        resolvedPort: 3389,
      ).listen(states.add);

      async.elapse(const Duration(seconds: 12));
      async.flushMicrotasks();
      subscription.cancel();

      expect(states.last.step, ConnectionStep.error);
      expect(states.last.errorType, MedLinkErrorType.wifi);
      expect(states.last.logMessage, contains('HUV_WIFI'));
      expect(
        states.last.logMessage,
        contains('aceptada por NetworkManager'),
      );
    });
  });

  test('Wi-Fi that never confirms without a response uses the generic message',
      () {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    when(() => mockWifiManager.getCurrentConnectionInfo()).thenAnswer(
      (_) async => const WifiConnectionInfo(
        ssid: 'OtraRed',
        interfaceName: 'Wi-Fi',
        gateway: '192.168.1.1',
      ),
    );
    when(() => mockWifiManager.connect(ssid: 'HUV_WIFI', password: null))
        .thenAnswer((_) async => '   ');

    fakeAsync((async) {
      final states = <WorkflowState>[];
      final subscription = workflowService.connect(
        subnets: ['10.0.0.0/8'],
        host: '192.168.1.100',
        user: '',
        domain: '',
        selectedWifi: 'HUV_WIFI',
        gateway: '',
        iface: '',
        resolvedPort: 3389,
      ).listen(states.add);

      async.elapse(const Duration(seconds: 12));
      async.flushMicrotasks();
      subscription.cancel();

      expect(states.last.step, ConnectionStep.error);
      expect(states.last.errorType, MedLinkErrorType.wifi);
      expect(states.last.logMessage, contains('HUV_WIFI'));
      expect(states.last.logMessage, isNot(contains('Respuesta')));
    });
  });

  test('a DNS lookup timeout is reported and the flow continues', () {
    _stubRoutes(mockRouteManager);
    when(() => mockNetworkDiagnostics.ping('nonexistent.invalid'))
        .thenAnswer((_) async => 20);
    when(() => mockNetworkDiagnostics.checkTcpPort('nonexistent.invalid', 3389))
        .thenAnswer((_) async => 25);
    when(() => mockRdpLauncher.isRdpClientAvailable())
        .thenAnswer((_) async => true);
    when(() => mockRdpLauncher.preLaunch()).thenAnswer((_) async => true);
    when(() => mockRdpLauncher.launchRdp(
          host: 'nonexistent.invalid',
          port: 3389,
          username: null,
          domain: null,
          profile: 'adaptive',
          measuredLatencyMs: 25,
        )).thenAnswer((_) async => 'RDP Launched');

    fakeAsync((async) {
      final states = <WorkflowState>[];
      final subscription = workflowService.connect(
        subnets: ['10.0.0.0/8'],
        host: 'nonexistent.invalid',
        user: '',
        domain: '',
        selectedWifi: '',
        gateway: '192.168.1.1',
        iface: 'Wi-Fi',
        resolvedPort: 3389,
      ).listen(states.add);

      async.elapse(const Duration(seconds: 10));
      async.flushMicrotasks();
      subscription.cancel();

      expect(
        states.map((state) => state.logMessage),
        contains(contains('4s')),
      );
      expect(states.last.step, ConnectionStep.done);
    });
  });

  test('route manager fills a missing gateway for the connected Wi-Fi',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    when(() => mockWifiManager.getCurrentConnectionInfo()).thenAnswer(
      (_) async => const WifiConnectionInfo(
        ssid: 'HUV_WIFI',
        interfaceName: 'wlan0',
        gateway: '',
      ),
    );
    when(() => mockRouteManager.getPrimaryDefaultRouteInfo()).thenAnswer(
      (_) async => {
        'gateway': '192.168.5.1',
        'interfaceName': 'WLAN0',
      },
    );
    _stubRoutes(mockRouteManager, gateway: '192.168.5.1', iface: 'WLAN0');
    _stubSuccessfulRdp(mockNetworkDiagnostics, mockRdpLauncher);

    final states = await workflowService.connect(
      subnets: ['10.0.0.0/8'],
      host: '192.168.1.100',
      user: '',
      domain: '',
      selectedWifi: 'HUV_WIFI',
      gateway: '',
      iface: '',
      resolvedPort: 3389,
    ).toList();

    expect(states.last.step, ConnectionStep.done);
    verify(() => mockRouteManager.enableSplitTunnel(
          hospitalSubnets: ['10.0.0.0/8'],
          gateway: '192.168.5.1',
          interfaceName: 'WLAN0',
        )).called(1);
  });

  test('missing routes after enabling the tunnel abort the flow', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    when(() => mockRouteManager.enableSplitTunnel(
          hospitalSubnets: ['10.0.0.0/8'],
          gateway: '192.168.1.1',
          interfaceName: 'Wi-Fi',
        )).thenAnswer((_) async => 'Rutas agregadas');
    when(() => mockRouteManager.verifyRoutes(
          hospitalSubnets: ['10.0.0.0/8'],
          gateway: '192.168.1.1',
          interfaceName: 'Wi-Fi',
        )).thenAnswer((_) async => ['10.0.0.0/8']);
    when(() => mockRouteManager.disableSplitTunnel())
        .thenAnswer((_) async => 'Revertido');

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
    expect(states.last.logMessage, contains('10.0.0.0/8'));
    verify(() => mockRouteManager.disableSplitTunnel()).called(1);
  });

  test('Android route verification failure rolls back and notifies', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    when(() => mockRouteManager.enableSplitTunnel(
          hospitalSubnets: ['10.0.0.0/8'],
          gateway: '192.168.1.1',
          interfaceName: 'Wi-Fi',
        )).thenAnswer((_) async => 'Rutas agregadas');
    when(() => mockRouteManager.verifyRoutes(
          hospitalSubnets: ['10.0.0.0/8'],
          gateway: '192.168.1.1',
          interfaceName: 'Wi-Fi',
        )).thenAnswer((_) async => ['10.0.0.0/8']);
    when(() => mockRouteManager.disableSplitTunnel())
        .thenAnswer((_) async => 'Revertido');
    _stubSuccessfulRdp(mockNetworkDiagnostics, mockRdpLauncher);

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

    expect(rolledBack, isTrue);
    expect(states.last.step, ConnectionStep.done);
    expect(
      states.map((state) => state.logMessage),
      contains(contains('Túnel dividido no disponible')),
    );
  });

  test('server selection errors are logged and the connection continues',
      () async {
    _stubRoutes(mockRouteManager);
    _stubSuccessfulRdp(mockNetworkDiagnostics, mockRdpLauncher);

    final states = await workflowService.connect(
      subnets: ['10.0.0.0/8'],
      host: '192.168.1.100',
      user: '',
      domain: '',
      selectedWifi: '',
      gateway: '192.168.1.1',
      iface: 'Wi-Fi',
      resolvedPort: 3389,
      onSelectServer: () async => throw Exception('sin presets'),
    ).toList();

    expect(
      states.map((state) => state.logMessage),
      contains(contains('sin presets')),
    );
    expect(states.last.step, ConnectionStep.done);
  });

  test('DNS failures do not abort the probe sequence', () async {
    _stubRoutes(mockRouteManager);
    when(() => mockNetworkDiagnostics.ping('nonexistent.invalid'))
        .thenAnswer((_) async => 20);
    when(() => mockNetworkDiagnostics.checkTcpPort('nonexistent.invalid', 3389))
        .thenAnswer((_) async => 25);
    when(() => mockRdpLauncher.isRdpClientAvailable())
        .thenAnswer((_) async => true);
    when(() => mockRdpLauncher.preLaunch()).thenAnswer((_) async => true);
    when(() => mockRdpLauncher.launchRdp(
          host: 'nonexistent.invalid',
          port: 3389,
          username: null,
          domain: null,
          profile: 'adaptive',
          measuredLatencyMs: 25,
        )).thenAnswer((_) async => 'RDP Launched');

    final states = await workflowService.connect(
      subnets: ['10.0.0.0/8'],
      host: 'nonexistent.invalid',
      user: '',
      domain: '',
      selectedWifi: '',
      gateway: '192.168.1.1',
      iface: 'Wi-Fi',
      resolvedPort: 3389,
    ).toList();

    final dnsFailure = states.where(
      (state) => state.step == ConnectionStep.preLaunch && state.isError,
    );
    expect(dnsFailure, isNotEmpty);
    expect(states.last.step, ConnectionStep.done);
  });

  test('ICMP failures carry the probe cause', () async {
    _stubRoutes(mockRouteManager);
    when(() => mockNetworkDiagnostics.ping('192.168.1.100'))
        .thenAnswer((_) async => null);
    when(() => mockNetworkDiagnostics.lastProbeError)
        .thenReturn('tiempo agotado');
    when(() => mockNetworkDiagnostics.checkTcpPort('192.168.1.100', 3389))
        .thenAnswer((_) async => 25);
    when(() => mockRdpLauncher.isRdpClientAvailable())
        .thenAnswer((_) async => true);
    when(() => mockRdpLauncher.preLaunch()).thenAnswer((_) async => true);
    when(() => mockRdpLauncher.launchRdp(
          host: '192.168.1.100',
          port: 3389,
          username: null,
          domain: null,
          profile: 'adaptive',
          measuredLatencyMs: 25,
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
    ).toList();

    expect(
      states.map((state) => state.logMessage),
      contains(contains('Causa: tiempo agotado')),
    );
    expect(states.last.step, ConnectionStep.done);
  });

  test('ICMP failures without a cause keep the generic message', () async {
    _stubRoutes(mockRouteManager);
    when(() => mockNetworkDiagnostics.ping('192.168.1.100'))
        .thenAnswer((_) async => null);
    when(() => mockNetworkDiagnostics.checkTcpPort('192.168.1.100', 3389))
        .thenAnswer((_) async => 25);
    when(() => mockRdpLauncher.isRdpClientAvailable())
        .thenAnswer((_) async => true);
    when(() => mockRdpLauncher.preLaunch()).thenAnswer((_) async => true);
    when(() => mockRdpLauncher.launchRdp(
          host: '192.168.1.100',
          port: 3389,
          username: null,
          domain: null,
          profile: 'adaptive',
          measuredLatencyMs: 25,
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
    ).toList();

    final icmp = states.firstWhere(
      (state) => state.logMessage.contains('ICMP'),
    );
    expect(icmp.isError, isTrue);
    expect(icmp.logMessage, isNot(contains('Causa:')));
    expect(states.last.step, ConnectionStep.done);
  });

  test('TCP failures report the probe cause and roll back', () async {
    _stubRoutes(mockRouteManager);
    when(() => mockNetworkDiagnostics.ping('192.168.1.100'))
        .thenAnswer((_) async => 20);
    when(() => mockNetworkDiagnostics.checkTcpPort('192.168.1.100', 3389))
        .thenAnswer((_) async => null);
    when(() => mockNetworkDiagnostics.lastProbeError)
        .thenReturn('conexión rechazada');
    when(() => mockRouteManager.disableSplitTunnel())
        .thenAnswer((_) async => 'Revertido');

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
    expect(states.last.logMessage, contains('conexión rechazada'));
    expect(states.last.logMessage, contains('3389'));
    verify(() => mockRouteManager.disableSplitTunnel()).called(1);
  });

  test('a missing RDP client aborts before launching', () async {
    _stubRoutes(mockRouteManager);
    when(() => mockNetworkDiagnostics.ping('192.168.1.100'))
        .thenAnswer((_) async => 20);
    when(() => mockNetworkDiagnostics.checkTcpPort('192.168.1.100', 3389))
        .thenAnswer((_) async => 25);
    when(() => mockRdpLauncher.isRdpClientAvailable())
        .thenAnswer((_) async => false);
    when(() => mockRouteManager.disableSplitTunnel())
        .thenAnswer((_) async => 'Revertido');

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
    expect(states.last.logMessage, contains('cliente RDP'));
    verifyNever(() => mockRdpLauncher.launchRdp(
          host: any(named: 'host'),
          port: any(named: 'port'),
          username: any(named: 'username'),
          domain: any(named: 'domain'),
          profile: any(named: 'profile'),
          measuredLatencyMs: any(named: 'measuredLatencyMs'),
        ));
  });

  test('a missing rdp:// handler aborts before launching', () async {
    _stubRoutes(mockRouteManager);
    when(() => mockNetworkDiagnostics.ping('192.168.1.100'))
        .thenAnswer((_) async => 20);
    when(() => mockNetworkDiagnostics.checkTcpPort('192.168.1.100', 3389))
        .thenAnswer((_) async => 25);
    when(() => mockRdpLauncher.isRdpClientAvailable())
        .thenAnswer((_) async => true);
    when(() => mockRdpLauncher.preLaunch()).thenAnswer((_) async => false);
    when(() => mockRouteManager.disableSplitTunnel())
        .thenAnswer((_) async => 'Revertido');

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
    expect(states.last.logMessage, contains('rdp://'));
  });
}
