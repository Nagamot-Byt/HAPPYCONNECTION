import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:medlink_connect/features/ui/home_controller.dart';
import 'package:medlink_connect/core/network_diagnostics.dart';
import 'package:medlink_connect/core/rdp_launcher.dart';
import 'package:medlink_connect/core/connection_workflow_service.dart';
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

void main() {
  late MockNetworkDiagnostics mockNetworkDiagnostics;
  late MockRouteManager mockRouteManager;
  late MockRdpLauncher mockRdpLauncher;
  late MockConnectionWorkflowService mockWorkflowService;
  late MockWifiManager mockWifiManager;
  late MockSettingsStorage mockSettingsStorage;
  late HomeController controller;

  setUp(() {
    mockNetworkDiagnostics = MockNetworkDiagnostics();
    mockRouteManager = MockRouteManager();
    mockRdpLauncher = MockRdpLauncher();
    mockWorkflowService = MockConnectionWorkflowService();
    mockWifiManager = MockWifiManager();
    mockSettingsStorage = MockSettingsStorage();

    when(() => mockSettingsStorage.init()).thenAnswer((_) async {});
    when(() => mockSettingsStorage.save()).thenAnswer((_) async {});

    when(() => mockSettingsStorage.hospitalSubnetsAsText).thenReturn('');
    when(() => mockSettingsStorage.gateway).thenReturn('');
    when(() => mockSettingsStorage.interfaceName).thenReturn('');
    when(() => mockSettingsStorage.rdpHost).thenReturn('');
    when(() => mockSettingsStorage.rdpPort).thenReturn(3389);
    when(() => mockSettingsStorage.rdpUsername).thenReturn('');
    when(() => mockSettingsStorage.rdpDomain).thenReturn('');
    when(() => mockSettingsStorage.rdpProfile).thenReturn('adaptive');
    when(() => mockSettingsStorage.wifiSsid).thenReturn('');

    controller = HomeController(
      settings: mockSettingsStorage,
      wifiManager: mockWifiManager,
      routeManager: mockRouteManager,
      networkDiagnostics: mockNetworkDiagnostics,
      rdpLauncher: mockRdpLauncher,
      workflowService: mockWorkflowService,
    );
  });

  group('HomeController Tests', () {
    test('initial state should be idle and not busy', () {
      expect(controller.step, equals(ConnectionStep.idle));
      expect(controller.busy, isFalse);
    });

    test(
        'runDiagnostics should use networkDiagnostics directly since it is not fully extracted',
        () async {
      when(() => mockNetworkDiagnostics.flushDns())
          .thenAnswer((_) async => 'DNS Flushed');
      when(() => mockNetworkDiagnostics.clearNetworkCaches())
          .thenAnswer((_) async => 'Caches Cleared');
      when(() => mockNetworkDiagnostics.ping('8.8.8.8'))
          .thenAnswer((_) async => 20);

      await controller.runDiagnostics();

      expect(controller.logs.isNotEmpty, isTrue);
      expect(controller.logs.any((l) => l.contains('DNS Flushed')), isTrue);
      expect(controller.logs.any((l) => l.contains('Ping a 8.8.8.8: 20ms')),
          isTrue);
    });

    test('applyServerPreset should update RDP fields', () {
      final preset = ServerPreset(
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

    test('connect rejects empty subnets or host', () async {
      controller.rdpHostCtrl.text = '';
      await controller.connect();
      expect(controller.logs.any((l) => l.contains('Configuración inválida')),
          isTrue);

      controller.rdpHostCtrl.text = '192.168.1.1';
      controller.subnetsCtrl.text = '';
      await controller.connect();
      expect(controller.logs.any((l) => l.contains('Configuración inválida')),
          isTrue);
    });

    test('dispose cleans up all TextEditingControllers without throwing', () {
      expect(() => controller.dispose(), returnsNormally);
    });
  });
}
