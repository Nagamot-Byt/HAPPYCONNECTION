import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gen/gen_l10n/app_localizations_es.dart';
import 'package:mocktail/mocktail.dart';
import 'package:medlink_connect/features/ui/home_controller.dart';
import 'package:medlink_connect/core/network_diagnostics.dart';
import 'package:medlink_connect/core/rdp_launcher.dart';
import 'package:medlink_connect/core/connection_workflow_service.dart';
import 'package:medlink_connect/core/exceptions.dart';
import 'package:medlink_connect/core/route_manager.dart';
import 'package:medlink_connect/core/wifi_manager.dart';
import 'package:medlink_connect/core/settings_storage.dart';

class MockNetworkDiagnostics extends Mock implements NetworkDiagnostics {}

class MockRouteManager extends Mock implements RouteManager {}

class MockRdpLauncher extends Mock implements RdpLauncher {}

class MockConnectionWorkflowService extends Mock
    implements ConnectionWorkflowService {}

class MockWifiManager extends Mock implements WifiManager {}

class MockSettingsStorage extends Mock implements SettingsStorage {}

void _stubWorkflowConnect(
  MockConnectionWorkflowService service,
  Stream<WorkflowState> Function() stream,
  Future<void> Function(Invocation invocation) beforeYield,
) {
  when(() => service.connect(
        subnets: const [],
        host: '192.168.1.100',
        user: '',
        domain: '',
        selectedWifi: '',
        gateway: '192.168.1.1',
        iface: 'wlan0',
        resolvedPort: 3389,
        rdpProfile: 'adaptive',
        wifiPassword: '',
        onSelectServer: any(named: 'onSelectServer'),
        onSplitTunnelEnabled: any(named: 'onSplitTunnelEnabled'),
        onSplitTunnelRolledBack: any(named: 'onSplitTunnelRolledBack'),
        onSplitTunnelUnavailable: any(named: 'onSplitTunnelUnavailable'),
      )).thenAnswer((invocation) async* {
    await beforeYield(invocation);
    yield* stream();
  });
}

void main() {
  late MockNetworkDiagnostics mockNetworkDiagnostics;
  late MockRouteManager mockRouteManager;
  late MockRdpLauncher mockRdpLauncher;
  late MockConnectionWorkflowService mockWorkflowService;
  late MockWifiManager mockWifiManager;
  late MockSettingsStorage mockSettingsStorage;
  late HomeController controller;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    mockNetworkDiagnostics = MockNetworkDiagnostics();
    mockRouteManager = MockRouteManager();
    mockRdpLauncher = MockRdpLauncher();
    mockWorkflowService = MockConnectionWorkflowService();
    mockWifiManager = MockWifiManager();
    mockSettingsStorage = MockSettingsStorage();

    when(() => mockSettingsStorage.init()).thenAnswer((_) async {});
    when(() => mockSettingsStorage.save()).thenAnswer((_) async {});

    when(() => mockSettingsStorage.gateway).thenReturn('');
    when(() => mockSettingsStorage.interfaceName).thenReturn('');
    when(() => mockSettingsStorage.rdpHost).thenReturn('');
    when(() => mockSettingsStorage.rdpPort).thenReturn(3389);
    when(() => mockSettingsStorage.rdpUsername).thenReturn('');
    when(() => mockSettingsStorage.rdpDomain).thenReturn('');
    when(() => mockSettingsStorage.rdpProfile).thenReturn('adaptive');
    when(() => mockSettingsStorage.preferMostStableServer).thenReturn(false);
    when(() => mockSettingsStorage.wifiSsid).thenReturn('');

    controller = HomeController(
      settings: mockSettingsStorage,
      wifiManager: mockWifiManager,
      routeManager: mockRouteManager,
      networkDiagnostics: mockNetworkDiagnostics,
      rdpLauncher: mockRdpLauncher,
      workflowService: mockWorkflowService,
      l10n: AppLocalizationsEs(),
    );
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('HomeController Tests', () {
    test('initial state should be idle and not busy', () {
      expect(controller.step, equals(ConnectionStep.idle));
      expect(controller.busy, isFalse);
    });

    test('platform capabilities gate Wi-Fi and RDP profile controls', () {
      expect(controller.wifiSupported, isTrue);
      expect(controller.rdpProfileSupported, isFalse);

      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(controller.wifiSupported, isTrue);
      expect(controller.rdpProfileSupported, isTrue);

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(controller.wifiSupported, isFalse);
      expect(controller.rdpProfileSupported, isFalse);
    });

    test('runDiagnostics pings the configured hospital gateway', () async {
      controller.gatewayCtrl.text = '192.168.1.1';
      when(() => mockNetworkDiagnostics.flushDns())
          .thenAnswer((_) async => 'DNS Flushed');
      when(() => mockNetworkDiagnostics.clearNetworkCaches())
          .thenAnswer((_) async => 'Caches Cleared');
      when(() => mockNetworkDiagnostics.ping('192.168.1.1'))
          .thenAnswer((_) async => 20);

      await controller.runDiagnostics();

      expect(controller.logs.isNotEmpty, isTrue);
      expect(controller.logs.any((l) => l.contains('DNS Flushed')), isTrue);
      expect(controller.logs.any((l) => l.contains('Ping a 192.168.1.1: 20ms')),
          isTrue);
    });

    test('runDiagnostics prefers the RDP host and skips when no target exists',
        () async {
      controller.rdpHostCtrl.text = '10.20.30.40';
      when(() => mockNetworkDiagnostics.flushDns())
          .thenAnswer((_) async => 'DNS Flushed');
      when(() => mockNetworkDiagnostics.clearNetworkCaches())
          .thenAnswer((_) async => 'Caches Cleared');
      when(() => mockNetworkDiagnostics.ping('10.20.30.40'))
          .thenAnswer((_) async => 8);

      await controller.runDiagnostics();
      expect(
          controller.logs.any((l) => l.contains('10.20.30.40: 8ms')), isTrue);

      controller.clearLogs();
      controller.rdpHostCtrl.text = '';
      await controller.runDiagnostics();
      expect(
          controller.logs
              .any((l) => l.contains('No hay host RDP ni gateway configurado')),
          isTrue);
    });

    test('runDiagnostics surfaces the probe failure cause', () async {
      controller.gatewayCtrl.text = '192.168.1.1';
      when(() => mockNetworkDiagnostics.flushDns())
          .thenAnswer((_) async => 'DNS Flushed');
      when(() => mockNetworkDiagnostics.clearNetworkCaches())
          .thenAnswer((_) async => 'Caches Cleared');
      when(() => mockNetworkDiagnostics.ping('192.168.1.1'))
          .thenAnswer((_) async => null);
      when(() => mockNetworkDiagnostics.lastProbeError)
          .thenReturn('inaccesible: sin ruta');

      await controller.runDiagnostics();

      expect(controller.logs.any((l) => l.contains('inaccesible: sin ruta')),
          isTrue);
    });

    test('typed errors select guidance without reading message text', () {
      controller.setErrorGuidance(
          const PrivilegeRequiredException('permiso requerido'));
      expect(controller.guidanceTitle, 'Faltan permisos de Administrador');

      controller.setErrorGuidance(
          const WifiConnectionException('no se pudo asociar'));
      expect(controller.guidanceTitle, 'Problema con la red Wi-Fi');

      controller
          .setErrorGuidance(const RouteConfigurationException('fallo de ruta'));
      expect(controller.guidanceTitle, 'Problema con rutas/gateway');

      controller.setErrorGuidance(const RdpTimeoutException('sin respuesta'));
      expect(controller.guidanceTitle, 'Problema con RDP/puerto 3389');
    });

    test('log entries keep error level without emoji', () {
      controller.log('ok', isError: false);
      controller.log('fallo', isError: true);

      expect(controller.logEntries.last.isError, isTrue);
      expect(controller.logs.last.contains('fallo'), isTrue);
      expect(controller.logs.last.contains('❌'), isFalse);
      expect(controller.logs.first.contains('✅'), isFalse);
    });

    test('applyServerPreset should update RDP fields', () {
      const preset = ServerPreset(
        id: 'test',
        label: 'Test Server',
        host: '10.0.0.1',
        port: 3389,
      );

      controller.applyServerPreset(preset, announce: false);

      expect(controller.rdpHostCtrl.text, equals('10.0.0.1'));
      expect(controller.rdpPortCtrl.text, equals('3389'));
      expect(controller.selectedServerPresetId, equals('test'));
    });

    test('diagnoseBestServerPreset chooses the lowest measured latency',
        () async {
      controller.serverPresets = const [
        ServerPreset(
          id: 'slow',
          label: 'Slow',
          host: '10.0.0.1',
          port: 3389,
        ),
        ServerPreset(
          id: 'fast',
          label: 'Fast',
          host: '10.0.0.2',
          port: 3389,
        ),
      ];
      when(() => mockNetworkDiagnostics.checkTcpPortDetailed('10.0.0.1', 3389))
          .thenAnswer((_) async => const NetworkProbeResult(value: 120));
      when(() => mockNetworkDiagnostics.checkTcpPortDetailed('10.0.0.2', 3389))
          .thenAnswer((_) async => const NetworkProbeResult(value: 25));

      final best = await controller.diagnoseBestServerPreset();

      expect(best?.id, 'fast');
      expect(controller.rdpHostCtrl.text, '10.0.0.2');
      expect(controller.selectedServerPresetId, 'fast');
    });

    test('connect allows an empty host when a configured preset can be chosen',
        () async {
      controller.serverPresets = const [
        ServerPreset(
          id: 'fast',
          label: 'Fast',
          host: '10.0.0.2',
          port: 3389,
        ),
      ];
      controller.preferMostStableServer = true;
      controller.gatewayCtrl.text = '192.168.1.1';
      controller.ifaceCtrl.text = 'Wi-Fi';
      controller.rdpPortCtrl.text = '3389';

      when(() => mockWorkflowService.connect(
            subnets: const [],
            host: '',
            user: '',
            domain: '',
            selectedWifi: '',
            gateway: '192.168.1.1',
            iface: 'Wi-Fi',
            resolvedPort: 3389,
            rdpProfile: 'adaptive',
            wifiPassword: '',
            onSelectServer: any(named: 'onSelectServer'),
            onSplitTunnelEnabled: any(named: 'onSplitTunnelEnabled'),
            onSplitTunnelRolledBack: any(named: 'onSplitTunnelRolledBack'),
            onSplitTunnelUnavailable: any(named: 'onSplitTunnelUnavailable'),
          )).thenAnswer((_) => Stream.value(const WorkflowState(
            step: ConnectionStep.done,
            logMessage: 'Conectado',
            isFinished: true,
          )));

      await controller.connect();

      expect(
        controller.logs.any((line) => line.contains('host RDP')),
        isFalse,
      );
      verify(() => mockWorkflowService.connect(
            subnets: const [],
            host: '',
            user: '',
            domain: '',
            selectedWifi: '',
            gateway: '192.168.1.1',
            iface: 'Wi-Fi',
            resolvedPort: 3389,
            rdpProfile: 'adaptive',
            wifiPassword: '',
            onSelectServer: any(named: 'onSelectServer'),
            onSplitTunnelEnabled: any(named: 'onSplitTunnelEnabled'),
            onSplitTunnelRolledBack: any(named: 'onSplitTunnelRolledBack'),
            onSplitTunnelUnavailable: any(named: 'onSplitTunnelUnavailable'),
          )).called(1);
    });

    test('init removes routes left by a previous session', () async {
      when(() => mockSettingsStorage.pendingSplitTunnelCleanup).thenReturn(
        const PendingSplitTunnelCleanup(
          subnets: ['10.0.0.0/8'],
          gateway: '192.168.1.1',
          interfaceName: 'Wi-Fi',
        ),
      );
      when(() => mockRouteManager.removeRoute(
            destinationCidr: '10.0.0.0/8',
            gateway: '192.168.1.1',
            interfaceName: 'Wi-Fi',
          )).thenAnswer((_) async => 'Ruta eliminada.');
      when(() => mockSettingsStorage.clearPendingSplitTunnelCleanup())
          .thenAnswer((_) async {});

      await controller.init();

      verify(() => mockRouteManager.removeRoute(
            destinationCidr: '10.0.0.0/8',
            gateway: '192.168.1.1',
            interfaceName: 'Wi-Fi',
          )).called(1);
      verify(() => mockSettingsStorage.clearPendingSplitTunnelCleanup())
          .called(1);
    });

    test('init keeps the saved gateway instead of overwriting it', () async {
      when(() => mockSettingsStorage.gateway).thenReturn('10.0.0.1');
      when(() => mockSettingsStorage.interfaceName).thenReturn('Guardada');
      when(() => mockSettingsStorage.pendingSplitTunnelCleanup)
          .thenReturn(null);
      when(() => mockWifiManager.scanNetworks()).thenAnswer((_) async => []);
      when(() => mockWifiManager.getCurrentConnectionInfo()).thenAnswer(
        (_) async => const WifiConnectionInfo(
          ssid: 'HUV_WIFI',
          interfaceName: 'wlan0',
          gateway: '192.168.1.1',
        ),
      );

      await controller.init();
      await pumpEventQueue();

      expect(controller.gatewayCtrl.text, '10.0.0.1');
      expect(controller.ifaceCtrl.text, 'Guardada');
      expect(controller.currentWifiSsid, 'HUV_WIFI');
    });

    test('disconnect skips native route cleanup on Apple platforms', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      when(() => mockSettingsStorage.clearPendingSplitTunnelCleanup())
          .thenAnswer((_) async {});

      await controller.disconnect();

      verifyNever(() => mockRouteManager.disableSplitTunnel());
      expect(controller.splitTunnelActive, isFalse);
      expect(controller.guidanceIsError, isFalse);
    });

    test('troubleshooter does not verify routes on Apple platforms', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      controller.rdpHostCtrl.text = '10.0.0.50';
      controller.preferMostStableServer = false;
      when(() => mockRouteManager.getPrimaryDefaultRouteInfo())
          .thenAnswer((_) async => {'gateway': '', 'interfaceName': 'en0'});
      when(() => mockRdpLauncher.isRdpClientAvailable())
          .thenAnswer((_) async => true);
      when(() => mockNetworkDiagnostics.ping('10.0.0.50'))
          .thenAnswer((_) async => 5);
      when(() => mockNetworkDiagnostics.checkTcpPortDetailed('10.0.0.50', 3389))
          .thenAnswer((_) async => const NetworkProbeResult(value: 10));

      await controller.runConnectionTroubleshooter();

      verifyNever(() => mockRouteManager.verifyRoutes(
            hospitalSubnets: any(named: 'hospitalSubnets'),
            gateway: any(named: 'gateway'),
            interfaceName: any(named: 'interfaceName'),
          ));
      expect(controller.guidanceIsError, isFalse);
    });

    test('fallback clears split tunnel state so a second connect is allowed',
        () async {
      controller.rdpHostCtrl.text = '192.168.1.100';
      controller.gatewayCtrl.text = '192.168.1.1';
      controller.ifaceCtrl.text = 'Wi-Fi';
      controller.rdpPortCtrl.text = '3389';

      when(() => mockSettingsStorage.clearPendingSplitTunnelCleanup())
          .thenAnswer((_) async {});
      when(() => mockWorkflowService.connect(
            subnets: const [],
            host: '192.168.1.100',
            user: '',
            domain: '',
            selectedWifi: '',
            gateway: '192.168.1.1',
            iface: 'Wi-Fi',
            resolvedPort: 3389,
            rdpProfile: 'adaptive',
            wifiPassword: '',
            onSelectServer: any(named: 'onSelectServer'),
            onSplitTunnelEnabled: any(named: 'onSplitTunnelEnabled'),
            onSplitTunnelRolledBack: any(named: 'onSplitTunnelRolledBack'),
            onSplitTunnelUnavailable: any(named: 'onSplitTunnelUnavailable'),
          )).thenAnswer((invocation) {
        final onUnavailable =
            invocation.namedArguments[#onSplitTunnelUnavailable] as Future<void>
                Function()?;
        return () async* {
          yield const WorkflowState(
            step: ConnectionStep.splitTunnel,
            logMessage: 'Preparando túnel',
          );
          await onUnavailable?.call();
          yield const WorkflowState(
            step: ConnectionStep.preLaunch,
            logMessage: 'Túnel no disponible',
            isError: true,
          );
          yield const WorkflowState(
            step: ConnectionStep.done,
            logMessage: 'Conectado',
            isFinished: true,
          );
        }();
      });

      await controller.connect();

      expect(controller.splitTunnelActive, isFalse);
      verifyNever(() => mockSettingsStorage.clearPendingSplitTunnelCleanup());

      await controller.connect();
      verifyNever(() => mockRouteManager.disableSplitTunnel());
    });

    test('split tunnel becomes active only after native enable callback',
        () async {
      controller.rdpHostCtrl.text = '192.168.1.100';
      controller.gatewayCtrl.text = '192.168.1.1';
      controller.ifaceCtrl.text = 'Wi-Fi';
      controller.rdpPortCtrl.text = '3389';

      when(() => mockSettingsStorage.setPendingSplitTunnelCleanup(
            subnets: any(named: 'subnets'),
            gateway: any(named: 'gateway'),
            interfaceName: any(named: 'interfaceName'),
          )).thenAnswer((_) async {});
      when(() => mockWorkflowService.connect(
            subnets: const [],
            host: '192.168.1.100',
            user: '',
            domain: '',
            selectedWifi: '',
            gateway: '192.168.1.1',
            iface: 'Wi-Fi',
            resolvedPort: 3389,
            rdpProfile: 'adaptive',
            wifiPassword: '',
            onSelectServer: any(named: 'onSelectServer'),
            onSplitTunnelEnabled: any(named: 'onSplitTunnelEnabled'),
            onSplitTunnelRolledBack: any(named: 'onSplitTunnelRolledBack'),
            onSplitTunnelUnavailable: any(named: 'onSplitTunnelUnavailable'),
          )).thenAnswer((invocation) {
        final onEnabled = invocation.namedArguments[#onSplitTunnelEnabled]
            as Future<void> Function(List<String>, String, String)?;
        return () async* {
          yield const WorkflowState(
            step: ConnectionStep.splitTunnel,
            logMessage: 'Preparando túnel',
          );
          expect(controller.splitTunnelActive, isFalse);
          await onEnabled?.call(['10.0.0.0/8'], '192.168.1.1', 'Wi-Fi');
          expect(controller.splitTunnelActive, isTrue);
          yield const WorkflowState(
            step: ConnectionStep.done,
            logMessage: 'Conectado',
            isFinished: true,
          );
        }();
      });

      await controller.connect();

      expect(controller.splitTunnelActive, isTrue);
    });

    test('runDiagnostics rejects an invalid host before native probes',
        () async {
      controller.rdpHostCtrl.text = 'host con espacios';
      when(() => mockNetworkDiagnostics.flushDns())
          .thenAnswer((_) async => 'DNS Flushed');
      when(() => mockNetworkDiagnostics.clearNetworkCaches())
          .thenAnswer((_) async => 'Caches Cleared');

      await controller.runDiagnostics();

      verifyNever(() => mockNetworkDiagnostics.ping(any()));
      expect(
        controller.logs.any((line) => line.contains('Configuración inválida')),
        isTrue,
      );
    });

    test('refreshWifiNetworks deduplicates and sorts SSIDs', () async {
      when(() => mockWifiManager.scanNetworks())
          .thenAnswer((_) async => ['Hospital', 'Anemia', 'Hospital']);

      await controller.refreshWifiNetworks(silent: true);

      expect(controller.wifiNetworks, ['Anemia', 'Hospital']);
    });

    test('manual Wi-Fi entry is used when no networks are returned', () {
      controller.selectedWifiSsid = null;
      controller.manualWifiCtrl.text = 'RedManual';

      expect(controller.resolvedWifiSsid(), 'RedManual');

      controller.selectManualWifi();

      expect(controller.selectedWifiSsid, controller.manualWifiOption);
      expect(controller.resolvedWifiSsid(), 'RedManual');
    });

    test('Wi-Fi scan errors are visible even during silent startup refresh',
        () async {
      when(() => mockWifiManager.scanNetworks())
          .thenThrow(const WifiConnectionException('nmcli no disponible'));

      await controller.refreshWifiNetworks(silent: true);

      expect(controller.wifiScanError, contains('nmcli no disponible'));
      expect(
        controller.logs.any((line) => line.contains('nmcli no disponible')),
        isTrue,
      );
    });

    test('a failed rescan drops the previous SSID list', () async {
      when(() => mockWifiManager.scanNetworks())
          .thenAnswer((_) async => ['HUV_WIFI', 'Invitados_HUV']);
      await controller.refreshWifiNetworks(silent: true);
      expect(controller.wifiNetworks, isNotEmpty);

      when(() => mockWifiManager.scanNetworks())
          .thenThrow(const WifiConnectionException('escaneo fallido'));

      await controller.refreshWifiNetworks();

      expect(controller.wifiNetworks, isEmpty);
      expect(controller.wifiScanError, contains('escaneo fallido'));
    });

    test('connect attempts selected Wi-Fi before requiring gateway/interface',
        () async {
      controller.rdpHostCtrl.text = '192.168.1.100';
      controller.rdpPortCtrl.text = '3389';
      controller.manualWifiCtrl.text = 'NuevaRed';
      controller.selectManualWifi();
      controller.gatewayCtrl.clear();
      controller.ifaceCtrl.clear();

      when(() => mockWifiManager.getCurrentConnectionInfo()).thenAnswer(
        (_) async => const WifiConnectionInfo(
          ssid: '',
          interfaceName: '',
          gateway: '',
        ),
      );
      when(() => mockRouteManager.getPrimaryDefaultRouteInfo())
          .thenAnswer((_) async => <String, String>{});
      when(() => mockWorkflowService.connect(
            subnets: const [],
            host: '192.168.1.100',
            user: '',
            domain: '',
            selectedWifi: 'NuevaRed',
            gateway: '',
            iface: '',
            resolvedPort: 3389,
            rdpProfile: 'adaptive',
            wifiPassword: '',
            onSelectServer: any(named: 'onSelectServer'),
            onSplitTunnelEnabled: any(named: 'onSplitTunnelEnabled'),
            onSplitTunnelRolledBack: any(named: 'onSplitTunnelRolledBack'),
            onSplitTunnelUnavailable: any(named: 'onSplitTunnelUnavailable'),
          )).thenAnswer((_) => Stream.value(const WorkflowState(
            step: ConnectionStep.done,
            logMessage: 'Conectado',
            isFinished: true,
          )));

      await controller.connect();

      verify(() => mockWorkflowService.connect(
            subnets: const [],
            host: '192.168.1.100',
            user: '',
            domain: '',
            selectedWifi: 'NuevaRed',
            gateway: '',
            iface: '',
            resolvedPort: 3389,
            rdpProfile: 'adaptive',
            wifiPassword: '',
            onSelectServer: any(named: 'onSelectServer'),
            onSplitTunnelEnabled: any(named: 'onSplitTunnelEnabled'),
            onSplitTunnelRolledBack: any(named: 'onSplitTunnelRolledBack'),
            onSplitTunnelUnavailable: any(named: 'onSplitTunnelUnavailable'),
          )).called(1);
    });

    test('saveSettings can clear a previously stored Wi-Fi SSID', () async {
      await controller.saveSettings();

      verify(() => mockSettingsStorage.wifiSsid = '').called(1);
    });

    test('troubleshooter refreshes gateway and interface after Wi-Fi sync',
        () async {
      controller.rdpHostCtrl.text = '10.0.0.50';
      controller.preferMostStableServer = false;
      when(() => mockWifiManager.getCurrentConnectionInfo()).thenAnswer(
        (_) async => const WifiConnectionInfo(
          ssid: 'HUV_WIFI',
          interfaceName: 'eth0',
          gateway: '192.168.1.1',
        ),
      );
      when(() => mockWorkflowService.hostCidrResolver)
          .thenReturn((host) async => ['10.0.0.50/32']);
      when(() => mockRouteManager.verifyRoutes(
            hospitalSubnets: ['10.0.0.50/32'],
            gateway: '192.168.1.1',
            interfaceName: 'eth0',
          )).thenAnswer((_) async => const <String>[]);
      when(() => mockRdpLauncher.isRdpClientAvailable())
          .thenAnswer((_) async => true);
      when(() => mockNetworkDiagnostics.ping('10.0.0.50'))
          .thenAnswer((_) async => 5);
      when(() => mockNetworkDiagnostics.checkTcpPortDetailed('10.0.0.50', 3389))
          .thenAnswer((_) async => const NetworkProbeResult(value: 10));

      await controller.runConnectionTroubleshooter();

      verify(() => mockRouteManager.verifyRoutes(
            hospitalSubnets: ['10.0.0.50/32'],
            gateway: '192.168.1.1',
            interfaceName: 'eth0',
          )).called(1);
    });

    test('a failed rollback keeps the split tunnel marked as active', () async {
      controller.rdpHostCtrl.text = '192.168.1.100';
      controller.gatewayCtrl.text = '192.168.1.1';
      controller.ifaceCtrl.text = 'Wi-Fi';

      when(() => mockSettingsStorage.setPendingSplitTunnelCleanup(
            subnets: any(named: 'subnets'),
            gateway: any(named: 'gateway'),
            interfaceName: any(named: 'interfaceName'),
          )).thenAnswer((_) async {});
      when(() => mockWorkflowService.connect(
            subnets: const [],
            host: '192.168.1.100',
            user: '',
            domain: '',
            selectedWifi: '',
            gateway: '192.168.1.1',
            iface: 'Wi-Fi',
            resolvedPort: 3389,
            rdpProfile: 'adaptive',
            wifiPassword: '',
            onSelectServer: any(named: 'onSelectServer'),
            onSplitTunnelEnabled: any(named: 'onSplitTunnelEnabled'),
            onSplitTunnelRolledBack: any(named: 'onSplitTunnelRolledBack'),
            onSplitTunnelUnavailable: any(named: 'onSplitTunnelUnavailable'),
          )).thenAnswer((invocation) {
        final onEnabled = invocation.namedArguments[#onSplitTunnelEnabled]
            as Future<void> Function(List<String>, String, String)?;
        return () async* {
          yield const WorkflowState(
            step: ConnectionStep.splitTunnel,
            logMessage: 'Preparando túnel',
          );
          await onEnabled?.call(['10.0.0.0/8'], '192.168.1.1', 'Wi-Fi');
          yield const WorkflowState(
            step: ConnectionStep.error,
            logMessage: 'No se pudo deshabilitar el túnel',
            isError: true,
            isFinished: true,
            errorType: MedLinkErrorType.route,
          );
        }();
      });

      await controller.connect();

      expect(controller.splitTunnelActive, isTrue);
    });

    test('reset is aborted when stale routes cannot be removed', () async {
      when(() => mockSettingsStorage.pendingSplitTunnelCleanup).thenReturn(
        const PendingSplitTunnelCleanup(
          subnets: ['10.0.0.0/8'],
          gateway: '192.168.1.1',
          interfaceName: 'Wi-Fi',
        ),
      );
      when(() => mockRouteManager.removeRoute(
            destinationCidr: '10.0.0.0/8',
            gateway: '192.168.1.1',
            interfaceName: 'Wi-Fi',
          )).thenThrow(
        const RouteConfigurationException('sin permisos'),
      );
      when(() => mockSettingsStorage.clear()).thenAnswer((_) async {});

      await controller.resetSettings();

      verifyNever(() => mockSettingsStorage.clear());
      expect(controller.guidanceTitle, 'Problema con rutas/gateway');
    });

    test('diagnoseBestServerPreset ignores unconfigured presets', () async {
      controller.serverPresets = const [
        ServerPreset(
          id: 'pending',
          label: 'Pendiente',
          host: 'pendiente',
          port: 3389,
        ),
      ];

      final best = await controller.diagnoseBestServerPreset();

      expect(best, isNull);
    });

    test('log keeps only the most recent entries', () {
      for (var i = 0; i < 600; i++) {
        controller.log('line $i');
      }

      expect(controller.logs.length, 500);
      expect(controller.logs.first, contains('line 100'));
      expect(controller.logs.last, contains('line 599'));
    });

    test('invalid RDP port falls back to 3389 and reports it', () {
      controller.rdpPortCtrl.text = '70000';

      expect(controller.parsePort(), 3389);
      expect(
        controller.logs.any((line) => line.contains('Puerto RDP inválido')),
        isTrue,
      );
    });

    test('connect rejects an empty host', () async {
      controller.rdpHostCtrl.text = '';
      await controller.connect();
      expect(controller.logs.any((l) => l.contains('Configuración inválida')),
          isTrue);
    });

    test('dispose cleans up all TextEditingControllers without throwing', () {
      expect(() => controller.dispose(), returnsNormally);
    });

    test('init without settings logs that storage is unavailable', () async {
      final bareController = HomeController(
        routeManager: mockRouteManager,
        networkDiagnostics: mockNetworkDiagnostics,
        rdpLauncher: mockRdpLauncher,
        workflowService: mockWorkflowService,
        l10n: AppLocalizationsEs(),
      );

      await bareController.init();

      expect(
        controller.logs.any((l) => l.contains('Almacenamiento no disponible')),
        isFalse,
      );
      expect(
          bareController.logs.any((l) => l.contains('no disponible')), isTrue);
      expect(bareController.serverPresets, isEmpty);
    });

    test('init loads hospital presets and keeps a valid saved selection',
        () async {
      when(() => mockSettingsStorage.pendingSplitTunnelCleanup)
          .thenReturn(null);
      when(() => mockSettingsStorage.selectedServerPresetId)
          .thenReturn('urgencias');
      when(() => mockWifiManager.scanNetworks()).thenAnswer((_) async => []);
      when(() => mockWifiManager.getCurrentConnectionInfo()).thenAnswer(
        (_) async => const WifiConnectionInfo(
          ssid: 'HUV_WIFI',
          interfaceName: 'wlan0',
          gateway: '192.168.1.1',
        ),
      );

      await controller.init();
      await pumpEventQueue();

      expect(controller.serverPresets.length, 5);
      expect(controller.selectedServerPresetId, 'urgencias');
      expect(controller.presetById('urgencias')?.host,
          'serv_urgencias.huv.gov.co');
    });

    test('init falls back to manual when the saved preset is unknown',
        () async {
      when(() => mockSettingsStorage.pendingSplitTunnelCleanup)
          .thenReturn(null);
      when(() => mockSettingsStorage.selectedServerPresetId)
          .thenReturn('desconocido');
      when(() => mockWifiManager.scanNetworks()).thenAnswer((_) async => []);
      when(() => mockWifiManager.getCurrentConnectionInfo()).thenAnswer(
        (_) async => const WifiConnectionInfo(
          ssid: '',
          interfaceName: '',
          gateway: '',
        ),
      );

      await controller.init();
      await pumpEventQueue();

      expect(controller.selectedServerPresetId, 'manual');
    });

    test('init surfaces a stale-tunnel cleanup failure without blocking',
        () async {
      when(() => mockSettingsStorage.pendingSplitTunnelCleanup)
          .thenThrow(StateError('prefs corruptos'));
      when(() => mockWifiManager.scanNetworks()).thenAnswer((_) async => []);
      when(() => mockWifiManager.getCurrentConnectionInfo()).thenAnswer(
        (_) async => const WifiConnectionInfo(
          ssid: '',
          interfaceName: '',
          gateway: '',
        ),
      );

      await controller.init();
      await pumpEventQueue();

      expect(controller.loaded, isTrue);
      expect(controller.logs.any((l) => l.contains('prefs corruptos')), isTrue);
    });

    test('resolvedWifiSsid prefers the scanned selection and the manual entry',
        () async {
      controller.manualWifiCtrl.text = 'RedManual';
      controller.selectedWifiSsid = null;
      expect(controller.resolvedWifiSsid(), 'RedManual');

      controller.selectManualWifi();
      expect(controller.selectedWifiSsid, controller.manualWifiOption);
      expect(controller.resolvedWifiSsid(), 'RedManual');

      when(() => mockWifiManager.scanNetworks())
          .thenAnswer((_) async => ['Escaneada']);
      await controller.refreshWifiNetworks(silent: true);

      controller.selectedWifiSsid = 'Escaneada';
      expect(controller.resolvedWifiSsid(), 'Escaneada');
    });

    test('refreshWifiNetworks reports progress when not silent', () async {
      when(() => mockWifiManager.scanNetworks())
          .thenAnswer((_) async => ['Hospital']);

      await controller.refreshWifiNetworks();

      expect(controller.wifiNetworksLoading, isFalse);
      expect(controller.wifiNetworks, ['Hospital']);
      expect(controller.logs.any((l) => l.contains('Buscando redes')), isTrue);
    });

    test('syncCurrentWifiInfo logs the current network when not silent',
        () async {
      when(() => mockWifiManager.getCurrentConnectionInfo()).thenAnswer(
        (_) async => const WifiConnectionInfo(
          ssid: 'HUV_WIFI',
          interfaceName: 'wlan0',
          gateway: '192.168.1.1',
        ),
      );

      final info = await controller.syncCurrentWifiInfo();

      expect(info?.ssid, 'HUV_WIFI');
      expect(controller.gatewayCtrl.text, '192.168.1.1');
      expect(controller.ifaceCtrl.text, 'wlan0');
      expect(controller.currentWifiSsid, 'HUV_WIFI');
    });

    test('syncCurrentWifiInfo reports when no Wi-Fi is active', () async {
      when(() => mockWifiManager.getCurrentConnectionInfo()).thenAnswer(
        (_) async => const WifiConnectionInfo(
          ssid: '',
          interfaceName: '',
          gateway: '',
        ),
      );

      final info = await controller.syncCurrentWifiInfo();

      expect(info, isNotNull);
      expect(controller.logs.any((l) => l.contains('No hay red Wi-Fi activa')),
          isTrue);
    });

    test('syncCurrentWifiInfo logs native failures when not silent', () async {
      when(() => mockWifiManager.getCurrentConnectionInfo())
          .thenThrow(const WifiConnectionException('nmcli error'));

      final info = await controller.syncCurrentWifiInfo();

      expect(info, isNull);
      expect(controller.logs.any((l) => l.contains('nmcli error')), isTrue);
    });

    test('friendlyRdpProfile maps every known profile', () {
      expect(controller.friendlyRdpProfile('stable'), 'Máxima estabilidad');
      expect(controller.friendlyRdpProfile('speed'), 'Máxima velocidad');
      expect(controller.friendlyRdpProfile('adaptive'), 'Adaptativo');
    });

    test('presetById returns null for unknown identifiers', () {
      expect(controller.presetById('no-existe'), isNull);
    });

    test('applyServerPreset announces the applied preset', () {
      controller.applyServerPreset(
        const ServerPreset(
          id: 'urgencias',
          label: 'Urgencias',
          host: 'serv_urgencias.huv.gov.co',
          port: 3389,
        ),
      );

      expect(controller.rdpHostCtrl.text, 'serv_urgencias.huv.gov.co');
      expect(
        controller.logs.any((l) => l.contains('Urgencias')),
        isTrue,
      );
    });

    test('diagnoseBestServerPreset falls back to the first configured preset',
        () async {
      controller.serverPresets = const [
        ServerPreset(
          id: 'pediatrico',
          label: 'Pediátrico',
          host: 'serv_pediatrico.huv.gov.co',
          port: 3389,
        ),
      ];
      when(() =>
          mockNetworkDiagnostics.checkTcpPortDetailed(
              'serv_pediatrico.huv.gov.co', 3389)).thenAnswer(
          (_) async => const NetworkProbeResult(error: 'timeout: sin ruta'));

      final best = await controller.diagnoseBestServerPreset();

      expect(best?.id, 'pediatrico');
      expect(
        controller.logs.any((l) => l.contains('no respondió')),
        isTrue,
      );
      expect(
        controller.logs.any((l) => l.contains('Ningún servidor')),
        isTrue,
      );
    });

    test('diagnoseBestServerPreset tolerates probe exceptions', () async {
      controller.serverPresets = const [
        ServerPreset(
          id: 'pediatrico',
          label: 'Pediátrico',
          host: 'serv_pediatrico.huv.gov.co',
          port: 3389,
        ),
      ];
      when(() => mockNetworkDiagnostics.checkTcpPortDetailed(
              'serv_pediatrico.huv.gov.co', 3389))
          .thenThrow(const RdpTimeoutException('puerto cerrado'));

      final best = await controller.diagnoseBestServerPreset();

      expect(best?.id, 'pediatrico');
      expect(
        controller.logs.any((l) => l.contains('puerto cerrado')),
        isTrue,
      );
    });

    test('warnIfDefaultRouteUsesHospitalInterface logs when interfaces match',
        () async {
      when(() => mockRouteManager.getPrimaryDefaultRouteInfo())
          .thenAnswer((_) async => {'interfaceName': 'wlan0', 'gateway': ''});

      await controller.warnIfDefaultRouteUsesHospitalInterface('wlan0');

      expect(
          controller.logs.any((l) => l.contains('ruta por defecto')), isTrue);
    });

    test('warnIfDefaultRouteUsesHospitalInterface stays silent otherwise',
        () async {
      when(() => mockRouteManager.getPrimaryDefaultRouteInfo()).thenAnswer(
          (_) async => {'interfaceName': 'eth0', 'gateway': '10.0.0.1'});

      await controller.warnIfDefaultRouteUsesHospitalInterface('wlan0');
      await controller.warnIfDefaultRouteUsesHospitalInterface('');
      when(() => mockRouteManager.getPrimaryDefaultRouteInfo())
          .thenThrow(StateError('sin ruta'));

      await controller.warnIfDefaultRouteUsesHospitalInterface('wlan0');

      expect(controller.logs.isEmpty, isTrue);
    });

    test('measureTcpPortWithRetryDetailed retries and keeps the best latency',
        () async {
      final probeResults = <NetworkProbeResult<int>>[
        const NetworkProbeResult(error: 'timeout'),
        const NetworkProbeResult(value: 45),
      ];
      when(() => mockNetworkDiagnostics.checkTcpPortDetailed('10.0.0.5', 3389))
          .thenAnswer((_) async => probeResults.removeAt(0));

      final result =
          await controller.measureTcpPortWithRetryDetailed('10.0.0.5', 3389);

      expect(result.latency, 45);
      expect(result.error, isNull);
      expect(controller.logs.any((l) => l.contains('Reintentando')), isTrue);
      expect(
          controller.logs.any((l) => l.contains('respondió en el reintento')),
          isTrue);
    });

    test('measureTcpPortWithRetryDetailed keeps the last probe error',
        () async {
      when(() => mockNetworkDiagnostics.checkTcpPortDetailed('10.0.0.5', 3389))
          .thenAnswer((_) async => const NetworkProbeResult(error: 'sin ruta'));

      final result =
          await controller.measureTcpPortWithRetryDetailed('10.0.0.5', 3389);

      expect(result.latency, isNull);
      expect(result.error, 'sin ruta');
    });

    test('runDiagnostics reports an unreachable target without cause',
        () async {
      controller.gatewayCtrl.text = '192.168.1.1';
      when(() => mockNetworkDiagnostics.flushDns())
          .thenAnswer((_) async => 'DNS Flushed');
      when(() => mockNetworkDiagnostics.clearNetworkCaches())
          .thenAnswer((_) async => 'Caches Cleared');
      when(() => mockNetworkDiagnostics.ping('192.168.1.1'))
          .thenAnswer((_) async => null);
      when(() => mockNetworkDiagnostics.lastProbeError).thenReturn(null);

      await controller.runDiagnostics();

      expect(
        controller.logs.any((l) => l.contains('inalcanzable')),
        isTrue,
      );
    });

    test('runDiagnostics survives ping and cache failures', () async {
      controller.gatewayCtrl.text = '192.168.1.1';
      when(() => mockNetworkDiagnostics.flushDns())
          .thenThrow(const PrivilegeRequiredException('sin sudo'));
      when(() => mockNetworkDiagnostics.clearNetworkCaches())
          .thenThrow(const RouteConfigurationException('pkexec falló'));
      when(() => mockNetworkDiagnostics.ping('192.168.1.1'))
          .thenThrow(const WifiConnectionException('ping no disponible'));

      await controller.runDiagnostics();

      expect(controller.step, ConnectionStep.idle);
      expect(controller.guidanceIsError, isFalse);
      expect(
        controller.logs.any((l) => l.contains('ping no disponible')),
        isTrue,
      );
    });

    test('runDiagnostics logs a save failure but keeps going', () async {
      controller.gatewayCtrl.text = '192.168.1.1';
      when(() => mockSettingsStorage.save())
          .thenThrow(StateError('disco lleno'));
      when(() => mockNetworkDiagnostics.flushDns())
          .thenAnswer((_) async => 'DNS Flushed');
      when(() => mockNetworkDiagnostics.clearNetworkCaches())
          .thenAnswer((_) async => 'Caches Cleared');
      when(() => mockNetworkDiagnostics.ping('192.168.1.1'))
          .thenAnswer((_) async => 12);

      await controller.runDiagnostics();

      expect(controller.logs.any((l) => l.contains('disco lleno')), isTrue);
      expect(controller.logs.any((l) => l.contains('192.168.1.1')), isTrue);
    });

    test('runDiagnostics rejects an invalid gateway before probing', () async {
      controller.rdpHostCtrl.text = '';
      controller.gatewayCtrl.text = '999.999.1.1';
      when(() => mockNetworkDiagnostics.flushDns())
          .thenAnswer((_) async => 'DNS Flushed');
      when(() => mockNetworkDiagnostics.clearNetworkCaches())
          .thenAnswer((_) async => 'Caches Cleared');

      await controller.runDiagnostics();

      verifyNever(() => mockNetworkDiagnostics.ping(any()));
      expect(
        controller.logs.any((l) => l.contains('Configuración inválida')),
        isTrue,
      );
    });

    test('connect without a host shows the missing-server guidance', () async {
      controller.gatewayCtrl.text = '192.168.1.1';
      controller.ifaceCtrl.text = 'wlan0';
      controller.preferMostStableServer = false;

      await controller.connect();

      verifyNever(() => mockWorkflowService.connect(
            subnets: any(named: 'subnets'),
            host: any(named: 'host'),
            user: any(named: 'user'),
            domain: any(named: 'domain'),
            selectedWifi: any(named: 'selectedWifi'),
            gateway: any(named: 'gateway'),
            iface: any(named: 'iface'),
            resolvedPort: any(named: 'resolvedPort'),
            rdpProfile: any(named: 'rdpProfile'),
            wifiPassword: any(named: 'wifiPassword'),
            onSelectServer: any(named: 'onSelectServer'),
            onSplitTunnelEnabled: any(named: 'onSplitTunnelEnabled'),
            onSplitTunnelRolledBack: any(named: 'onSplitTunnelRolledBack'),
            onSplitTunnelUnavailable: any(named: 'onSplitTunnelUnavailable'),
          ));
      expect(controller.guidanceTitle, 'Falta el servidor RDP');
      expect(controller.guidanceIsError, isTrue);
    });

    test('connect detects the default route when no Wi-Fi is selected',
        () async {
      controller.rdpHostCtrl.text = '192.168.1.100';
      controller.gatewayCtrl.clear();
      controller.ifaceCtrl.clear();
      controller.rdpPortCtrl.text = '3389';

      when(() => mockRouteManager.getPrimaryDefaultRouteInfo()).thenAnswer(
        (_) async => {'gateway': '192.168.5.1', 'interfaceName': 'wlan0'},
      );
      when(() => mockWorkflowService.connect(
            subnets: const [],
            host: '192.168.1.100',
            user: '',
            domain: '',
            selectedWifi: '',
            gateway: '192.168.5.1',
            iface: 'wlan0',
            resolvedPort: 3389,
            rdpProfile: 'adaptive',
            wifiPassword: '',
            onSelectServer: any(named: 'onSelectServer'),
            onSplitTunnelEnabled: any(named: 'onSplitTunnelEnabled'),
            onSplitTunnelRolledBack: any(named: 'onSplitTunnelRolledBack'),
            onSplitTunnelUnavailable: any(named: 'onSplitTunnelUnavailable'),
          )).thenAnswer((_) => Stream.value(const WorkflowState(
            step: ConnectionStep.done,
            logMessage: 'Conectado',
            isFinished: true,
          )));

      await controller.connect();

      expect(controller.gatewayCtrl.text, '192.168.5.1');
      expect(controller.ifaceCtrl.text, 'wlan0');
      expect(controller.step, ConnectionStep.done);
    });

    test('connect without gateway or interface shows network-data guidance',
        () async {
      controller.rdpHostCtrl.text = '192.168.1.100';
      controller.gatewayCtrl.clear();
      controller.ifaceCtrl.clear();
      when(() => mockRouteManager.getPrimaryDefaultRouteInfo())
          .thenAnswer((_) async => <String, String>{});

      await controller.connect();

      verifyNever(() => mockWorkflowService.connect(
            subnets: any(named: 'subnets'),
            host: any(named: 'host'),
            user: any(named: 'user'),
            domain: any(named: 'domain'),
            selectedWifi: any(named: 'selectedWifi'),
            gateway: any(named: 'gateway'),
            iface: any(named: 'iface'),
            resolvedPort: any(named: 'resolvedPort'),
            rdpProfile: any(named: 'rdpProfile'),
            wifiPassword: any(named: 'wifiPassword'),
            onSelectServer: any(named: 'onSelectServer'),
            onSplitTunnelEnabled: any(named: 'onSplitTunnelEnabled'),
            onSplitTunnelRolledBack: any(named: 'onSplitTunnelRolledBack'),
            onSplitTunnelUnavailable: any(named: 'onSplitTunnelUnavailable'),
          ));
      expect(controller.guidanceIsError, isTrue);
      expect(
        controller.logs.any((l) => l.contains('Faltan gateway o interfaz')),
        isTrue,
      );
    });

    test('connect closes a previous tunnel before reconnecting', () async {
      controller.rdpHostCtrl.text = '192.168.1.100';
      controller.gatewayCtrl.text = '192.168.1.1';
      controller.ifaceCtrl.text = 'wlan0';
      controller.rdpPortCtrl.text = '3389';

      when(() => mockSettingsStorage.setPendingSplitTunnelCleanup(
            subnets: any(named: 'subnets'),
            gateway: any(named: 'gateway'),
            interfaceName: any(named: 'interfaceName'),
          )).thenAnswer((_) async {});
      when(() => mockSettingsStorage.clearPendingSplitTunnelCleanup())
          .thenAnswer((_) async {});

      Stream<WorkflowState> firstStream() {
        return () async* {
          yield const WorkflowState(
            step: ConnectionStep.splitTunnel,
            logMessage: 'Preparando túnel',
          );
        }();
      }

      _stubWorkflowConnect(
          mockWorkflowService, firstStream, (invocation) async {});

      // Primera conexión que deja el túnel activo.
      await controller.connect();
      expect(controller.splitTunnelActive, isFalse);

      // Activar el túnel mediante el callback nativo.
      _stubWorkflowConnect(
        mockWorkflowService,
        firstStream,
        (invocation) async {
          final onEnabled = invocation.namedArguments[#onSplitTunnelEnabled]
              as Future<void> Function(List<String>, String, String)?;
          await onEnabled?.call(['10.0.0.0/8'], '192.168.1.1', 'wlan0');
        },
      );
      await controller.connect();
      expect(controller.splitTunnelActive, isTrue);

      when(() => mockRouteManager.disableSplitTunnel())
          .thenAnswer((_) async => 'Túnel cerrado');
      _stubWorkflowConnect(
        mockWorkflowService,
        firstStream,
        (invocation) async {},
      );

      await controller.connect();

      verify(() => mockRouteManager.disableSplitTunnel()).called(1);
      verify(() => mockSettingsStorage.clearPendingSplitTunnelCleanup())
          .called(1);
      expect(controller.splitTunnelActive, isFalse);
    });

    test('connect aborts when the previous tunnel cannot be closed', () async {
      controller.rdpHostCtrl.text = '192.168.1.100';
      controller.gatewayCtrl.text = '192.168.1.1';
      controller.ifaceCtrl.text = 'wlan0';

      when(() => mockSettingsStorage.setPendingSplitTunnelCleanup(
            subnets: any(named: 'subnets'),
            gateway: any(named: 'gateway'),
            interfaceName: any(named: 'interfaceName'),
          )).thenAnswer((_) async {});

      _stubWorkflowConnect(
        mockWorkflowService,
        () async* {
          yield const WorkflowState(
            step: ConnectionStep.splitTunnel,
            logMessage: 'Preparando túnel',
          );
        },
        (invocation) async {
          final onEnabled = invocation.namedArguments[#onSplitTunnelEnabled]
              as Future<void> Function(List<String>, String, String)?;
          await onEnabled?.call(['10.0.0.0/8'], '192.168.1.1', 'wlan0');
        },
      );
      await controller.connect();
      expect(controller.splitTunnelActive, isTrue);

      when(() => mockRouteManager.disableSplitTunnel()).thenThrow(
        const RouteConfigurationException('route delete falló'),
      );

      await controller.connect();

      // Solo la primera conexión llegó al workflow; la segunda aborta al
      // cerrar el túnel previo.
      verify(() => mockWorkflowService.connect(
            subnets: const [],
            host: '192.168.1.100',
            user: '',
            domain: '',
            selectedWifi: '',
            gateway: '192.168.1.1',
            iface: 'wlan0',
            resolvedPort: 3389,
            rdpProfile: 'adaptive',
            wifiPassword: '',
            onSelectServer: any(named: 'onSelectServer'),
            onSplitTunnelEnabled: any(named: 'onSplitTunnelEnabled'),
            onSplitTunnelRolledBack: any(named: 'onSplitTunnelRolledBack'),
            onSplitTunnelUnavailable: any(named: 'onSplitTunnelUnavailable'),
          )).called(1);
      verify(() => mockRouteManager.disableSplitTunnel()).called(1);
      expect(controller.guidanceTitle, 'Problema con rutas/gateway');
    });

    test('connect resets the step when the workflow closes early', () async {
      controller.rdpHostCtrl.text = '192.168.1.100';
      controller.gatewayCtrl.text = '192.168.1.1';
      controller.ifaceCtrl.text = 'wlan0';
      controller.rdpPortCtrl.text = '3389';

      when(() => mockWorkflowService.connect(
            subnets: const [],
            host: '192.168.1.100',
            user: '',
            domain: '',
            selectedWifi: '',
            gateway: '192.168.1.1',
            iface: 'wlan0',
            resolvedPort: 3389,
            rdpProfile: 'adaptive',
            wifiPassword: '',
            onSelectServer: any(named: 'onSelectServer'),
            onSplitTunnelEnabled: any(named: 'onSplitTunnelEnabled'),
            onSplitTunnelRolledBack: any(named: 'onSplitTunnelRolledBack'),
            onSplitTunnelUnavailable: any(named: 'onSplitTunnelUnavailable'),
          )).thenAnswer((_) => Stream.value(const WorkflowState(
            step: ConnectionStep.diagnostics,
            logMessage: 'Preparando diagnóstico',
          )));

      await controller.connect();

      expect(controller.step, ConnectionStep.idle);
      expect(controller.busy, isFalse);
    });

    test('connect auto-selects the best server through the workflow callback',
        () async {
      controller.serverPresets = const [
        ServerPreset(
          id: 'fast',
          label: 'Fast',
          host: '10.0.0.2',
          port: 3389,
        ),
      ];
      controller.preferMostStableServer = true;
      controller.gatewayCtrl.text = '192.168.1.1';
      controller.ifaceCtrl.text = 'wlan0';
      controller.rdpPortCtrl.text = '3389';

      when(() => mockNetworkDiagnostics.checkTcpPortDetailed('10.0.0.2', 3389))
          .thenAnswer((_) async => const NetworkProbeResult(value: 30));
      when(() => mockWorkflowService.connect(
            subnets: const [],
            host: '',
            user: '',
            domain: '',
            selectedWifi: '',
            gateway: '192.168.1.1',
            iface: 'wlan0',
            resolvedPort: 3389,
            rdpProfile: 'adaptive',
            wifiPassword: '',
            onSelectServer: any(named: 'onSelectServer'),
            onSplitTunnelEnabled: any(named: 'onSplitTunnelEnabled'),
            onSplitTunnelRolledBack: any(named: 'onSplitTunnelRolledBack'),
            onSplitTunnelUnavailable: any(named: 'onSplitTunnelUnavailable'),
          )).thenAnswer((invocation) {
        final onSelectServer = invocation.namedArguments[#onSelectServer]
            as Future<({String host, int port})?> Function()?;
        return () async* {
          final selected = await onSelectServer?.call();
          yield WorkflowState(
            step: ConnectionStep.done,
            logMessage:
                'Conectado a ${selected == null ? 'manual' : selected.host}',
            isFinished: true,
          );
        }();
      });

      await controller.connect();

      expect(controller.rdpHostCtrl.text, '10.0.0.2');
      expect(
        controller.logs.any((l) => l.contains('Seleccionando automáticamente')),
        isTrue,
      );
      expect(controller.logs.any((l) => l.contains('Conectado a 10.0.0.2')),
          isTrue);
    });

    test('connect clears the pending cleanup when the tunnel rolls back',
        () async {
      controller.rdpHostCtrl.text = '192.168.1.100';
      controller.gatewayCtrl.text = '192.168.1.1';
      controller.ifaceCtrl.text = 'wlan0';

      when(() => mockSettingsStorage.setPendingSplitTunnelCleanup(
            subnets: any(named: 'subnets'),
            gateway: any(named: 'gateway'),
            interfaceName: any(named: 'interfaceName'),
          )).thenAnswer((_) async {});
      when(() => mockSettingsStorage.clearPendingSplitTunnelCleanup())
          .thenAnswer((_) async {});

      when(() => mockWorkflowService.connect(
            subnets: const [],
            host: '192.168.1.100',
            user: '',
            domain: '',
            selectedWifi: '',
            gateway: '192.168.1.1',
            iface: 'wlan0',
            resolvedPort: 3389,
            rdpProfile: 'adaptive',
            wifiPassword: '',
            onSelectServer: any(named: 'onSelectServer'),
            onSplitTunnelEnabled: any(named: 'onSplitTunnelEnabled'),
            onSplitTunnelRolledBack: any(named: 'onSplitTunnelRolledBack'),
            onSplitTunnelUnavailable: any(named: 'onSplitTunnelUnavailable'),
          )).thenAnswer((invocation) {
        final onEnabled = invocation.namedArguments[#onSplitTunnelEnabled]
            as Future<void> Function(List<String>, String, String)?;
        final onRolledBack = invocation.namedArguments[#onSplitTunnelRolledBack]
            as Future<void> Function()?;
        return () async* {
          yield const WorkflowState(
            step: ConnectionStep.splitTunnel,
            logMessage: 'Preparando túnel',
          );
          await onEnabled?.call(['10.0.0.0/8'], '192.168.1.1', 'wlan0');
          await onRolledBack?.call();
          yield const WorkflowState(
            step: ConnectionStep.done,
            logMessage: 'Conectado sin túnel',
            isFinished: true,
          );
        }();
      });

      await controller.connect();

      verify(() => mockSettingsStorage.clearPendingSplitTunnelCleanup())
          .called(1);
      expect(controller.splitTunnelActive, isFalse);
    });

    test('disconnect on Linux disables the tunnel and restores guidance',
        () async {
      when(() => mockRouteManager.disableSplitTunnel())
          .thenAnswer((_) async => 'Túnel dividido deshabilitado');
      when(() => mockSettingsStorage.clearPendingSplitTunnelCleanup())
          .thenAnswer((_) async {});

      await controller.disconnect();

      verify(() => mockRouteManager.disableSplitTunnel()).called(1);
      expect(controller.splitTunnelActive, isFalse);
      expect(controller.guidanceIsError, isFalse);
      expect(controller.step, ConnectionStep.idle);
    });

    test('disconnect tolerates a failing cleanup-record removal', () async {
      when(() => mockRouteManager.disableSplitTunnel())
          .thenAnswer((_) async => 'Túnel dividido deshabilitado');
      when(() => mockSettingsStorage.clearPendingSplitTunnelCleanup())
          .thenThrow(StateError('prefs corruptos'));

      await controller.disconnect();

      expect(controller.logs.any((l) => l.contains('prefs corruptos')), isTrue);
      expect(controller.guidanceIsError, isFalse);
    });

    test('disconnect maps native failures to guidance', () async {
      when(() => mockRouteManager.disableSplitTunnel())
          .thenThrow(const RouteConfigurationException('ip no encontrado'));

      await controller.disconnect();

      expect(controller.guidanceIsError, isTrue);
      expect(
          controller.logs.any((l) => l.contains('ip no encontrado')), isTrue);
    });

    test('resetSettings disables an active tunnel and clears the form',
        () async {
      controller.rdpHostCtrl.text = '192.168.1.100';
      controller.gatewayCtrl.text = '192.168.1.1';
      controller.ifaceCtrl.text = 'wlan0';

      when(() => mockSettingsStorage.setPendingSplitTunnelCleanup(
            subnets: any(named: 'subnets'),
            gateway: any(named: 'gateway'),
            interfaceName: any(named: 'interfaceName'),
          )).thenAnswer((_) async {});
      when(() => mockSettingsStorage.pendingSplitTunnelCleanup)
          .thenReturn(null);
      when(() => mockSettingsStorage.selectedServerPresetId).thenReturn('');
      when(() => mockSettingsStorage.clear()).thenAnswer((_) async {});
      when(() => mockWifiManager.scanNetworks()).thenAnswer((_) async => []);
      when(() => mockWifiManager.getCurrentConnectionInfo()).thenAnswer(
        (_) async => const WifiConnectionInfo(
          ssid: '',
          interfaceName: '',
          gateway: '',
        ),
      );
      when(() => mockRouteManager.disableSplitTunnel())
          .thenAnswer((_) async => 'Túnel deshabilitado');

      // Deja el túnel activo mediante una conexión previa.
      when(() => mockWorkflowService.connect(
            subnets: const [],
            host: '192.168.1.100',
            user: '',
            domain: '',
            selectedWifi: '',
            gateway: '192.168.1.1',
            iface: 'wlan0',
            resolvedPort: 3389,
            rdpProfile: 'adaptive',
            wifiPassword: '',
            onSelectServer: any(named: 'onSelectServer'),
            onSplitTunnelEnabled: any(named: 'onSplitTunnelEnabled'),
            onSplitTunnelRolledBack: any(named: 'onSplitTunnelRolledBack'),
            onSplitTunnelUnavailable: any(named: 'onSplitTunnelUnavailable'),
          )).thenAnswer((invocation) {
        final onEnabled = invocation.namedArguments[#onSplitTunnelEnabled]
            as Future<void> Function(List<String>, String, String)?;
        return () async* {
          yield const WorkflowState(
            step: ConnectionStep.splitTunnel,
            logMessage: 'Preparando túnel',
          );
          await onEnabled?.call(['10.0.0.0/8'], '192.168.1.1', 'wlan0');
          yield const WorkflowState(
            step: ConnectionStep.done,
            logMessage: 'Conectado',
            isFinished: true,
          );
        }();
      });
      await controller.connect();
      expect(controller.splitTunnelActive, isTrue);

      await controller.resetSettings();
      await pumpEventQueue();

      verify(() => mockRouteManager.disableSplitTunnel()).called(1);
      verify(() => mockSettingsStorage.clear()).called(1);
      expect(controller.rdpHostCtrl.text, isEmpty);
      expect(controller.rdpPortCtrl.text, '3389');
      expect(controller.wifiPasswordCtrl.text, isEmpty);
      expect(controller.logs.any((l) => l.contains('Ajustes restablecidos')),
          isTrue);
    });

    test('resetSettings surfaces storage failures as guidance', () async {
      when(() => mockSettingsStorage.pendingSplitTunnelCleanup)
          .thenReturn(null);
      when(() => mockSettingsStorage.clear())
          .thenThrow(StateError('prefs corruptos'));

      await controller.resetSettings();

      expect(controller.guidanceIsError, isTrue);
      expect(controller.logs.any((l) => l.contains('prefs corruptos')), isTrue);
    });

    test('troubleshooter reports findings when Wi-Fi is missing', () async {
      controller.rdpHostCtrl.text = '10.0.0.50';
      controller.gatewayCtrl.text = '192.168.1.1';
      controller.ifaceCtrl.text = 'wlan0';
      controller.preferMostStableServer = false;
      when(() => mockWifiManager.getCurrentConnectionInfo()).thenAnswer(
        (_) async => const WifiConnectionInfo(
          ssid: '',
          interfaceName: '',
          gateway: '',
        ),
      );
      when(() => mockRdpLauncher.isRdpClientAvailable())
          .thenAnswer((_) async => true);
      when(() => mockNetworkDiagnostics.ping('10.0.0.50'))
          .thenAnswer((_) async => 5);
      when(() => mockNetworkDiagnostics.checkTcpPortDetailed('10.0.0.50', 3389))
          .thenAnswer((_) async => const NetworkProbeResult(value: 10));

      await controller.runConnectionTroubleshooter();

      expect(controller.guidanceIsError, isTrue);
      expect(
        controller.guidanceBullets
            .any((b) => b.contains('No hay una red Wi-Fi activa')),
        isTrue,
      );
    });

    test('troubleshooter reports invalid gateway and interface findings',
        () async {
      controller.rdpHostCtrl.text = '10.0.0.50';
      controller.preferMostStableServer = false;
      // El sistema reporta valores no válidos; syncCurrentWifiInfo los
      // copia a los controladores y el sanitizador debe rechazarlos.
      when(() => mockWifiManager.getCurrentConnectionInfo()).thenAnswer(
        (_) async => const WifiConnectionInfo(
          ssid: 'HUV_WIFI',
          interfaceName: 'wlan\t0',
          gateway: '999.1.1.1',
        ),
      );
      when(() => mockRdpLauncher.isRdpClientAvailable())
          .thenAnswer((_) async => true);
      when(() => mockNetworkDiagnostics.ping('10.0.0.50'))
          .thenAnswer((_) async => 5);
      when(() => mockNetworkDiagnostics.checkTcpPortDetailed('10.0.0.50', 3389))
          .thenAnswer((_) async => const NetworkProbeResult(value: 10));

      await controller.runConnectionTroubleshooter();

      expect(controller.guidanceIsError, isTrue);
      final findingsText = controller.guidanceBullets.join(' ');
      expect(findingsText.contains('Puerta de enlace'), isTrue);
      expect(findingsText.contains('Interfaz de red'), isTrue);
    });

    test('troubleshooter reports a missing RDP client as a finding', () async {
      controller.rdpHostCtrl.text = '10.0.0.50';
      controller.gatewayCtrl.text = '192.168.1.1';
      controller.ifaceCtrl.text = 'wlan0';
      controller.preferMostStableServer = false;
      when(() => mockWifiManager.getCurrentConnectionInfo()).thenAnswer(
        (_) async => const WifiConnectionInfo(
          ssid: 'HUV_WIFI',
          interfaceName: 'wlan0',
          gateway: '192.168.1.1',
        ),
      );
      when(() => mockRdpLauncher.isRdpClientAvailable())
          .thenAnswer((_) async => false);
      when(() => mockNetworkDiagnostics.ping('10.0.0.50'))
          .thenAnswer((_) async => 5);
      when(() => mockNetworkDiagnostics.checkTcpPortDetailed('10.0.0.50', 3389))
          .thenAnswer((_) async => const NetworkProbeResult(value: 10));

      await controller.runConnectionTroubleshooter();

      expect(
        controller.guidanceBullets
            .any((b) => b.contains('cliente RDP disponible')),
        isTrue,
      );
    });

    test('troubleshooter reports missing hospital routes as a finding',
        () async {
      controller.rdpHostCtrl.text = '10.0.0.50';
      controller.gatewayCtrl.text = '192.168.1.1';
      controller.ifaceCtrl.text = 'wlan0';
      controller.preferMostStableServer = false;
      when(() => mockWifiManager.getCurrentConnectionInfo()).thenAnswer(
        (_) async => const WifiConnectionInfo(
          ssid: 'HUV_WIFI',
          interfaceName: 'wlan0',
          gateway: '192.168.1.1',
        ),
      );
      when(() => mockRdpLauncher.isRdpClientAvailable())
          .thenAnswer((_) async => true);
      when(() => mockWorkflowService.hostCidrResolver)
          .thenReturn((host) async => ['10.0.0.50/32']);
      when(() => mockRouteManager.verifyRoutes(
            hospitalSubnets: ['10.0.0.50/32'],
            gateway: '192.168.1.1',
            interfaceName: 'wlan0',
          )).thenAnswer((_) async => ['10.0.0.50/32']);
      when(() => mockNetworkDiagnostics.ping('10.0.0.50'))
          .thenAnswer((_) async => 5);
      when(() => mockNetworkDiagnostics.checkTcpPortDetailed('10.0.0.50', 3389))
          .thenAnswer((_) async => const NetworkProbeResult(value: 10));

      await controller.runConnectionTroubleshooter();

      expect(
        controller.guidanceBullets.any((b) => b.contains('faltan rutas')),
        isTrue,
      );
    });

    test('troubleshooter reports a missing RDP host as a finding', () async {
      controller.gatewayCtrl.text = '192.168.1.1';
      controller.ifaceCtrl.text = 'wlan0';
      controller.preferMostStableServer = false;
      when(() => mockWifiManager.getCurrentConnectionInfo()).thenAnswer(
        (_) async => const WifiConnectionInfo(
          ssid: 'HUV_WIFI',
          interfaceName: 'wlan0',
          gateway: '192.168.1.1',
        ),
      );
      when(() => mockRdpLauncher.isRdpClientAvailable())
          .thenAnswer((_) async => true);

      await controller.runConnectionTroubleshooter();

      expect(
        controller.guidanceBullets.any((b) => b.contains('host o IP')),
        isTrue,
      );
    });

    test('troubleshooter reports an invalid RDP host as a finding', () async {
      controller.rdpHostCtrl.text = '-host-invalido-';
      controller.gatewayCtrl.text = '192.168.1.1';
      controller.ifaceCtrl.text = 'wlan0';
      controller.preferMostStableServer = false;
      when(() => mockWifiManager.getCurrentConnectionInfo()).thenAnswer(
        (_) async => const WifiConnectionInfo(
          ssid: 'HUV_WIFI',
          interfaceName: 'wlan0',
          gateway: '192.168.1.1',
        ),
      );
      when(() => mockRdpLauncher.isRdpClientAvailable())
          .thenAnswer((_) async => true);

      await controller.runConnectionTroubleshooter();

      expect(
        controller.guidanceBullets.any((b) => b.contains('valor no es válido')),
        isTrue,
      );
    });

    test('troubleshooter reports ICMP failure and TCP failure findings',
        () async {
      controller.rdpHostCtrl.text = '10.0.0.50';
      controller.gatewayCtrl.text = '192.168.1.1';
      controller.ifaceCtrl.text = 'wlan0';
      controller.rdpPortCtrl.text = '3389';
      controller.preferMostStableServer = false;
      when(() => mockWifiManager.getCurrentConnectionInfo()).thenAnswer(
        (_) async => const WifiConnectionInfo(
          ssid: 'HUV_WIFI',
          interfaceName: 'wlan0',
          gateway: '192.168.1.1',
        ),
      );
      when(() => mockRdpLauncher.isRdpClientAvailable())
          .thenAnswer((_) async => true);
      when(() => mockNetworkDiagnostics.ping('10.0.0.50'))
          .thenAnswer((_) async => null);
      when(() => mockNetworkDiagnostics.lastProbeError)
          .thenReturn('timeout: destino inalcanzable');
      when(() => mockNetworkDiagnostics.checkTcpPortDetailed('10.0.0.50', 3389))
          .thenAnswer(
              (_) async => const NetworkProbeResult(error: 'timeout: closed'));

      await controller.runConnectionTroubleshooter();

      expect(
        controller.logs.any((l) => l.contains('timeout: destino inalcanzable')),
        isTrue,
      );
      expect(
        controller.guidanceBullets.any((b) => b.contains('no respondió')),
        isTrue,
      );
    });

    test('troubleshooter reports an unreachable host without a probe cause',
        () async {
      controller.rdpHostCtrl.text = '10.0.0.50';
      controller.gatewayCtrl.text = '192.168.1.1';
      controller.ifaceCtrl.text = 'wlan0';
      controller.preferMostStableServer = false;
      when(() => mockWifiManager.getCurrentConnectionInfo()).thenAnswer(
        (_) async => const WifiConnectionInfo(
          ssid: 'HUV_WIFI',
          interfaceName: 'wlan0',
          gateway: '192.168.1.1',
        ),
      );
      when(() => mockRdpLauncher.isRdpClientAvailable())
          .thenAnswer((_) async => true);
      when(() => mockNetworkDiagnostics.ping('10.0.0.50'))
          .thenAnswer((_) async => null);
      when(() => mockNetworkDiagnostics.lastProbeError).thenReturn(null);
      when(() => mockNetworkDiagnostics.checkTcpPortDetailed('10.0.0.50', 3389))
          .thenAnswer((_) async => const NetworkProbeResult(error: 'timeout'));

      await controller.runConnectionTroubleshooter();

      expect(
        controller.logs.any((l) => l.contains('no respondió a ICMP')),
        isTrue,
      );
      expect(
        controller.logs.any((l) => l.contains('No se pudo abrir TCP')),
        isTrue,
      );
    });

    test('troubleshooter maps overall failures to error guidance', () async {
      when(() => mockSettingsStorage.save())
          .thenThrow(StateError('disco lleno'));

      await controller.runConnectionTroubleshooter();

      expect(controller.step, ConnectionStep.error);
      expect(controller.guidanceIsError, isTrue);
    });

    test('connectSelectedWifi requires a selection', () async {
      controller.selectedWifiSsid = null;
      controller.manualWifiCtrl.text = '';

      final connected =
          await controller.connectSelectedWifi(requireSelection: true);

      expect(connected, isFalse);
      expect(
        controller.logs.any((l) => l.contains('No hay Wi-Fi seleccionado')),
        isTrue,
      );
    });

    test('connectSelectedWifi rejects an invalid SSID', () async {
      controller.manualWifiCtrl.text =
          'Red con caracteres de control \u0001invalidos';

      final connected =
          await controller.connectSelectedWifi(requireSelection: true);

      expect(connected, isFalse);
      expect(
        controller.logs.any((l) => l.contains('Configuración inválida')),
        isTrue,
      );
      verifyNever(() => mockWifiManager.connect(
            ssid: any(named: 'ssid'),
            password: any(named: 'password'),
          ));
    });

    test('connectSelectedWifi reports platforms without native Wi-Fi',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final connected =
          await controller.connectSelectedWifi(requireSelection: true);

      expect(connected, isFalse);
      expect(
        controller.logs.any((l) => l.contains('no está disponible')),
        isTrue,
      );
    });

    test('connectWifiOnly connects and saves the configuration', () {
      fakeAsync((async) {
        controller.manualWifiCtrl.text = 'HUV_WIFI';
        controller.selectManualWifi();
        when(() => mockWifiManager.connect(ssid: 'HUV_WIFI', password: ''))
            .thenAnswer((_) async => 'Solicitud enviada');
        when(() => mockWifiManager.getCurrentConnectionInfo()).thenAnswer(
          (_) async => const WifiConnectionInfo(
            ssid: 'HUV_WIFI',
            interfaceName: 'wlan0',
            gateway: '192.168.5.1',
          ),
        );

        var completed = false;
        controller.connectWifiOnly().then((_) => completed = true);
        async.elapse(const Duration(seconds: 30));
        async.flushMicrotasks();

        expect(completed, isTrue);
        expect(controller.guidanceIsError, isFalse);
        expect(controller.guidanceTitle, isNotNull);
        expect(controller.gatewayCtrl.text, '192.168.5.1');
        expect(controller.ifaceCtrl.text, 'wlan0');
        expect(controller.wifiPasswordCtrl.text, isEmpty);
        verify(() => mockSettingsStorage.save()).called(1);
      });
    });

    test('connectWifiOnly waits for missing gateway details', () {
      fakeAsync((async) {
        controller.manualWifiCtrl.text = 'HUV_WIFI';
        controller.selectManualWifi();
        var infoCalls = 0;
        when(() => mockWifiManager.connect(ssid: 'HUV_WIFI', password: ''))
            .thenAnswer((_) async => 'Solicitud enviada');
        when(() => mockWifiManager.getCurrentConnectionInfo()).thenAnswer(
          (_) async => infoCalls++ == 0
              ? const WifiConnectionInfo(
                  ssid: 'HUV_WIFI',
                  interfaceName: 'wlan0',
                  gateway: '',
                )
              : const WifiConnectionInfo(
                  ssid: 'HUV_WIFI',
                  interfaceName: 'wlan0',
                  gateway: '192.168.5.1',
                ),
        );

        var completed = false;
        controller.connectWifiOnly().then((_) => completed = true);
        async.elapse(const Duration(seconds: 60));
        async.flushMicrotasks();

        expect(completed, isTrue);
        expect(controller.guidanceIsError, isFalse);
        expect(controller.gatewayCtrl.text, '192.168.5.1');
        expect(
          controller.logs.any((l) => l.contains('HUV_WIFI')),
          isTrue,
        );
      });
    });

    test('connectWifiOnly shows failure guidance when the Wi-Fi never confirms',
        () {
      fakeAsync((async) {
        controller.manualWifiCtrl.text = 'HUV_WIFI';
        controller.selectManualWifi();
        when(() => mockWifiManager.connect(ssid: 'HUV_WIFI', password: ''))
            .thenAnswer((_) async => 'Solicitud enviada');
        when(() => mockWifiManager.getCurrentConnectionInfo()).thenAnswer(
          (_) async => const WifiConnectionInfo(
            ssid: 'OTRA_RED',
            interfaceName: 'wlan0',
            gateway: '192.168.5.1',
          ),
        );

        var completed = false;
        controller.connectWifiOnly().then((_) => completed = true);
        async.elapse(const Duration(seconds: 60));
        async.flushMicrotasks();

        expect(completed, isTrue);
        expect(controller.guidanceIsError, isTrue);
        expect(
          controller.logs.any((l) => l.contains('HUV_WIFI')),
          isTrue,
        );
        expect(controller.wifiPasswordCtrl.text, isEmpty);
      });
    });

    test('connectWifiOnly maps native exceptions to error guidance', () async {
      controller.manualWifiCtrl.text = 'HUV_WIFI';
      controller.selectManualWifi();
      when(() => mockWifiManager.connect(ssid: 'HUV_WIFI', password: ''))
          .thenThrow(const WifiConnectionException('nmcli falló'));

      await controller.connectWifiOnly();

      expect(controller.guidanceIsError, isTrue);
      expect(controller.wifiPasswordCtrl.text, isEmpty);
    });
  });
}
