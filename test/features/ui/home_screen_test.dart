import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import 'package:medlink_connect/core/connection_workflow_service.dart';
import 'package:medlink_connect/core/injection.dart';
import 'package:medlink_connect/core/network_diagnostics.dart';
import 'package:medlink_connect/core/rdp_launcher.dart';
import 'package:medlink_connect/core/route_manager.dart';
import 'package:medlink_connect/core/settings_storage.dart';
import 'package:medlink_connect/core/theme_controller.dart';
import 'package:medlink_connect/core/wifi_manager.dart';
import 'package:medlink_connect/features/ui/home_controller.dart';
import 'package:medlink_connect/features/ui/home_screen.dart';

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
  late ThemeController themeController;

  void stubStorageDefaults() {
    when(() => mockSettingsStorage.init()).thenAnswer((_) async {});
    when(() => mockSettingsStorage.save()).thenAnswer((_) async {});
    when(() => mockSettingsStorage.clear()).thenAnswer((_) async {});
    when(() => mockSettingsStorage.pendingSplitTunnelCleanup)
        .thenReturn(null);
    when(() => mockSettingsStorage.setPendingSplitTunnelCleanup(
          subnets: any(named: 'subnets'),
          gateway: any(named: 'gateway'),
          interfaceName: any(named: 'interfaceName'),
        )).thenAnswer((_) async {});
    when(() => mockSettingsStorage.clearPendingSplitTunnelCleanup())
        .thenAnswer((_) async {});
    when(() => mockSettingsStorage.hospitalSubnetsAsText).thenReturn('');
    when(() => mockSettingsStorage.gateway).thenReturn('');
    when(() => mockSettingsStorage.interfaceName).thenReturn('');
    when(() => mockSettingsStorage.rdpHost).thenReturn('');
    when(() => mockSettingsStorage.rdpPort).thenReturn(3389);
    when(() => mockSettingsStorage.rdpUsername).thenReturn('');
    when(() => mockSettingsStorage.rdpDomain).thenReturn('');
    when(() => mockSettingsStorage.rdpProfile).thenReturn('adaptive');
    when(() => mockSettingsStorage.preferMostStableServer).thenReturn(false);
    when(() => mockSettingsStorage.wifiSsid).thenReturn('');
    when(() => mockSettingsStorage.selectedServerPresetId).thenReturn('manual');
    when(() => mockSettingsStorage.themeMode).thenReturn(ThemeMode.dark);
  }

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('es'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: HomeScreen(),
      ),
    );
    await tester.pumpAndSettle();
  }

  HomeController controllerOf(WidgetTester tester) =>
      Provider.of<HomeController>(
        tester.element(find.text('MedLink Connect')),
        listen: false,
      );

  String chipText(WidgetTester tester) {
    final chip = tester.widget<Chip>(find.byType(Chip));
    return (chip.label as Text).data!;
  }

  void stubConnectWithStream(
    Stream<WorkflowState> Function(
      Future<void> Function(List<String>, String, String)? onSplitTunnelEnabled,
    ) build,
  ) {
    when(() => mockWorkflowService.connect(
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
        )).thenAnswer((invocation) {
      final onEnabled = invocation.namedArguments[#onSplitTunnelEnabled]
          as Future<void> Function(List<String>, String, String)?;
      return build(onEnabled);
    });
  }

  Future<void> fillConnectableFields(
    WidgetTester tester,
    HomeController controller,
  ) async {
    controller.subnetsCtrl.text = '10.0.0.0/8';
    controller.rdpHostCtrl.text = '10.0.0.50';
    controller.gatewayCtrl.text = '192.168.1.1';
    controller.ifaceCtrl.text = 'wlan0';
    await tester.pump();
  }

  Future<void> tapConnect(WidgetTester tester) async {
    final button = find.ancestor(
      of: find.text('Conectar y abrir RDP'),
      matching: find.bySubtype<FilledButton>(),
    );
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
  }

  Future<void> settleChip(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  setUp(() async {
    await getIt.reset();
    mockNetworkDiagnostics = MockNetworkDiagnostics();
    mockRouteManager = MockRouteManager();
    mockRdpLauncher = MockRdpLauncher();
    mockWorkflowService = MockConnectionWorkflowService();
    mockWifiManager = MockWifiManager();
    mockSettingsStorage = MockSettingsStorage();

    stubStorageDefaults();
    themeController = ThemeController(mockSettingsStorage);

    getIt.registerSingleton<SettingsStorage>(mockSettingsStorage);
    getIt.registerSingleton<WifiManager>(mockWifiManager);
    getIt.registerSingleton<RouteManager>(mockRouteManager);
    getIt.registerSingleton<NetworkDiagnostics>(mockNetworkDiagnostics);
    getIt.registerSingleton<RdpLauncher>(mockRdpLauncher);
    getIt.registerSingleton<ConnectionWorkflowService>(mockWorkflowService);
    getIt.registerSingleton<ThemeController>(themeController);

    when(() => mockWifiManager.scanNetworks())
        .thenAnswer((_) async => ['HUV_WIFI', 'Invitados_HUV']);
    when(() => mockWifiManager.getCurrentConnectionInfo()).thenAnswer(
      (_) async => const WifiConnectionInfo(
        ssid: 'HUV_WIFI',
        interfaceName: 'wlan0',
        gateway: '192.168.5.1',
      ),
    );
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('renders the shell and the current Wi-Fi network', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await pumpHome(tester);

      expect(find.text('MedLink Connect'), findsOneWidget);
      expect(find.text('Wi-Fi actual: HUV_WIFI'), findsOneWidget);
      expect(chipText(tester), 'Listo para conectar');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('the status chip follows each workflow step', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final gates = List.generate(5, (_) => Completer<void>());
      stubConnectWithStream(
        (onEnabled) => () async* {
          yield const WorkflowState(
            step: ConnectionStep.diagnostics,
            logMessage: 'Preparando',
          );
          await gates[0].future;
          await onEnabled?.call(['10.0.0.0/8'], '192.168.1.1', 'wlan0');
          yield const WorkflowState(
            step: ConnectionStep.idle,
            logMessage: 'Túnel activo',
          );
          await gates[1].future;
          yield const WorkflowState(
            step: ConnectionStep.splitTunnel,
            logMessage: 'Rutas',
          );
          await gates[2].future;
          yield const WorkflowState(
            step: ConnectionStep.preLaunch,
            logMessage: 'Verificando',
          );
          await gates[3].future;
          yield const WorkflowState(
            step: ConnectionStep.launchRdp,
            logMessage: 'Lanzando',
          );
          await gates[4].future;
          yield const WorkflowState(
            step: ConnectionStep.done,
            logMessage: 'Listo',
            isFinished: true,
          );
        }(),
      );

      await pumpHome(tester);
      await fillConnectableFields(tester, controllerOf(tester));

      await tapConnect(tester);
      await settleChip(tester);
      expect(chipText(tester), 'Preparando conexión…');

      gates[0].complete();
      await settleChip(tester);
      expect(chipText(tester), 'Túnel dividido activo');

      gates[1].complete();
      await settleChip(tester);
      expect(chipText(tester), 'Configurando rutas…');

      gates[2].complete();
      await settleChip(tester);
      expect(chipText(tester), 'Verificando destino y cliente RDP…');

      gates[3].complete();
      await settleChip(tester);
      expect(chipText(tester), 'Lanzando RDP…');

      gates[4].complete();
      await settleChip(tester);
      expect(chipText(tester), 'Conectado');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('shows the error step when the workflow fails', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      stubConnectWithStream(
        (_) => () async* {
          yield const WorkflowState(
            step: ConnectionStep.error,
            logMessage: 'fallo de red',
            isError: true,
            isFinished: true,
          );
        }(),
      );

      await pumpHome(tester);
      await fillConnectableFields(tester, controllerOf(tester));

      await tapConnect(tester);
      await settleChip(tester);

      expect(chipText(tester), 'Error');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('cancelling the reset dialog leaves settings untouched',
      (tester) async {
    await pumpHome(tester);

    await tester.tap(find.byTooltip('Restablecer ajustes'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Se borrarán las subredes, credenciales RDP y preferencias guardadas. '
        '¿Continuar?',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    verifyNever(() => mockSettingsStorage.clear());
  });

  testWidgets('confirming the reset clears settings and the theme',
      (tester) async {
    await pumpHome(tester);
    expect(themeController.mode, ThemeMode.dark);

    await tester.tap(find.byTooltip('Restablecer ajustes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restablecer'));
    await tester.pumpAndSettle();

    verify(() => mockSettingsStorage.clear()).called(1);
    expect(themeController.mode, ThemeMode.system);
  });
}
