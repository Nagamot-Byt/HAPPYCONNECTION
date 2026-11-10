import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_gen/gen_l10n/app_localizations_es.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import 'package:medlink_connect/core/connection_workflow_service.dart';
import 'package:medlink_connect/core/exceptions.dart';
import 'package:medlink_connect/core/network_diagnostics.dart';
import 'package:medlink_connect/core/rdp_launcher.dart';
import 'package:medlink_connect/core/route_manager.dart';
import 'package:medlink_connect/core/settings_storage.dart';
import 'package:medlink_connect/core/wifi_manager.dart';
import 'package:medlink_connect/features/ui/home_controller.dart';
import 'package:medlink_connect/features/ui/widgets/connection_action_buttons.dart';
import 'package:medlink_connect/features/ui/widgets/connection_logs_widget.dart';
import 'package:medlink_connect/features/ui/widgets/glass_container.dart';
import 'package:medlink_connect/features/ui/widgets/guidance_panel.dart';
import 'package:medlink_connect/features/ui/widgets/network_diagnostics_view.dart';
import 'package:medlink_connect/features/ui/widgets/server_selection_panel.dart';

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

  Future<void> pumpPanel(
    WidgetTester tester,
    Widget panel, {
    Brightness brightness = Brightness.dark,
  }) {
    return tester.pumpWidget(
      ChangeNotifierProvider<HomeController>.value(
        value: controller,
        child: MaterialApp(
          locale: const Locale('es'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
            body: SingleChildScrollView(child: panel),
          ),
        ),
      ),
    );
  }

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
  }

  Future<void> initLoadedController() async {
    stubStorageDefaults();
    when(() => mockWifiManager.scanNetworks())
        .thenAnswer((_) async => ['HUV_WIFI', 'Invitados_HUV']);
    when(() => mockWifiManager.getCurrentConnectionInfo()).thenAnswer(
      (_) async => const WifiConnectionInfo(
        ssid: 'HUV_WIFI',
        interfaceName: 'wlan0',
        gateway: '192.168.5.1',
      ),
    );
    await controller.init();
  }

  setUp(() {
    mockNetworkDiagnostics = MockNetworkDiagnostics();
    mockRouteManager = MockRouteManager();
    mockRdpLauncher = MockRdpLauncher();
    mockWorkflowService = MockConnectionWorkflowService();
    mockWifiManager = MockWifiManager();
    mockSettingsStorage = MockSettingsStorage();
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

  group('GlassContainer', () {
    testWidgets('renders its child inside a clipped surface', (tester) async {
      await pumpPanel(
        tester,
        const GlassContainer(child: Text('contenido del panel')),
      );

      expect(find.text('contenido del panel'), findsOneWidget);
      expect(find.byType(ClipRRect), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('honors a custom border radius', (tester) async {
      await pumpPanel(
        tester,
        const GlassContainer(borderRadius: 30, child: SizedBox.shrink()),
      );

      final clip = tester.widget<ClipRRect>(find.byType(ClipRRect));
      expect(clip.borderRadius, BorderRadius.circular(30));
    });

    testWidgets('uses the light theme defaults when bright', (tester) async {
      await pumpPanel(
        tester,
        const GlassContainer(child: Text('claro')),
        brightness: Brightness.light,
      );

      final container = tester.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color!.a, closeTo(0.78, 0.01));
    });
  });

  IconButton clearButton(WidgetTester tester) => tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.delete_sweep_outlined),
          matching: find.bySubtype<IconButton>(),
        ),
      );

  group('ConnectionLogsWidget', () {
    testWidgets('shows the empty state and disables clearing',
        (tester) async {
      await pumpPanel(tester, const ConnectionLogsWidget());

      expect(find.text('No hay actividad reciente.'), findsOneWidget);
      expect(clearButton(tester).onPressed, isNull);
    });

    testWidgets('lists entries and clears them on demand', (tester) async {
      controller.log('Iniciando sesión de diagnóstico');
      controller.log('Fallo de red', isError: true);
      await pumpPanel(tester, const ConnectionLogsWidget());

      expect(
        find.textContaining('Iniciando sesión de diagnóstico'),
        findsOneWidget,
      );
      expect(find.textContaining('Fallo de red'), findsOneWidget);
      expect(clearButton(tester).onPressed, isNotNull);

      await tester.tap(find.byIcon(Icons.delete_sweep_outlined));
      await tester.pumpAndSettle();

      expect(find.text('No hay actividad reciente.'), findsOneWidget);
      expect(find.textContaining('Fallo de red'), findsNothing);
    });

    testWidgets('colors error entries differently', (tester) async {
      controller.log('Fallo de red', isError: true);
      await pumpPanel(tester, const ConnectionLogsWidget());

      final text = tester.widget<Text>(find.textContaining('Fallo de red'));
      expect(text.style!.color, const Color(0xFFFF9AA7));
    });
  });

  group('GuidancePanel', () {
    testWidgets('renders nothing without guidance', (tester) async {
      controller.clearGuidance();
      await pumpPanel(tester, GuidancePanel(controller: controller));

      expect(find.byType(GlassContainer), findsNothing);
    });

    testWidgets('renders the title and bullets for guidance', (tester) async {
      controller.setGuidance(
        'Todo en orden',
        bullets: ['Red detectada', 'Rutas listas'],
      );
      await pumpPanel(tester, GuidancePanel(controller: controller));

      expect(find.text('Todo en orden'), findsOneWidget);
      expect(find.text('• Red detectada'), findsOneWidget);
      expect(find.text('• Rutas listas'), findsOneWidget);
      expect(find.byIcon(Icons.tips_and_updates_outlined), findsOneWidget);
    });

    testWidgets('uses the warning icon for error guidance', (tester) async {
      controller.setGuidance('Algo falló', isError: true);
      await pumpPanel(tester, GuidancePanel(controller: controller));

      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });
  });

  Widget reactiveButtons() => ListenableBuilder(
        listenable: controller,
        builder: (_, __) => ConnectionActionButtons(controller: controller),
      );

  group('ConnectionActionButtons', () {
    testWidgets('disables every action until settings are loaded',
        (tester) async {
      await pumpPanel(tester, ConnectionActionButtons(controller: controller));

      FilledButton buttonWithLabel(String label) =>
          tester.widget<FilledButton>(
            find.ancestor(
              of: find.text(label),
              matching: find.bySubtype<FilledButton>(),
            ),
          );
      OutlinedButton outlinedWithLabel(String label) =>
          tester.widget<OutlinedButton>(
            find.ancestor(
              of: find.text(label),
              matching: find.bySubtype<OutlinedButton>(),
            ),
          );

      expect(buttonWithLabel('Revisar conexión').onPressed, isNull);
      expect(buttonWithLabel('Ayudarme a corregir').onPressed, isNull);
      expect(buttonWithLabel('Conectar y abrir RDP').onPressed, isNull);
      expect(outlinedWithLabel('Desconectar túnel').onPressed, isNull);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    testWidgets('enables actions once loaded, except disconnect',
        (tester) async {
      await initLoadedController();
      await pumpPanel(tester, ConnectionActionButtons(controller: controller));

      FilledButton buttonWithLabel(String label) =>
          tester.widget<FilledButton>(
            find.ancestor(
              of: find.text(label),
              matching: find.bySubtype<FilledButton>(),
            ),
          );
      OutlinedButton outlinedWithLabel(String label) =>
          tester.widget<OutlinedButton>(
            find.ancestor(
              of: find.text(label),
              matching: find.bySubtype<OutlinedButton>(),
            ),
          );

      expect(buttonWithLabel('Revisar conexión').onPressed, isNotNull);
      expect(buttonWithLabel('Ayudarme a corregir').onPressed, isNotNull);
      expect(buttonWithLabel('Conectar y abrir RDP').onPressed, isNotNull);
      expect(outlinedWithLabel('Desconectar túnel').onPressed, isNull);
    });

    testWidgets('shows a spinner and blocks buttons while connecting',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await initLoadedController();
        controller.subnetsCtrl.text = '10.0.0.0/8';
        controller.rdpHostCtrl.text = '10.0.0.50';
        controller.gatewayCtrl.text = '192.168.1.1';
        controller.ifaceCtrl.text = 'wlan0';
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
              onSplitTunnelRolledBack:
                  any(named: 'onSplitTunnelRolledBack'),
              onSplitTunnelUnavailable:
                  any(named: 'onSplitTunnelUnavailable'),
            )).thenAnswer((_) async* {
          await Completer<void>().future;
        });

        await pumpPanel(tester, reactiveButtons());
        await tester.tap(find.text('Conectar y abrir RDP'));
        await tester.pump();

        expect(controller.busy, isTrue);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        final diagnostics = tester.widget<FilledButton>(
          find.ancestor(
            of: find.text('Revisar conexión'),
            matching: find.bySubtype<FilledButton>(),
          ),
        );
        expect(diagnostics.onPressed, isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('enables disconnect once the tunnel is active',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await initLoadedController();
        controller.subnetsCtrl.text = '10.0.0.0/8';
        controller.rdpHostCtrl.text = '10.0.0.50';
        controller.gatewayCtrl.text = '192.168.1.1';
        controller.ifaceCtrl.text = 'wlan0';
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
              onSplitTunnelRolledBack:
                  any(named: 'onSplitTunnelRolledBack'),
              onSplitTunnelUnavailable:
                  any(named: 'onSplitTunnelUnavailable'),
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
        when(() => mockRouteManager.disableSplitTunnel())
            .thenAnswer((_) async => 'Túnel deshabilitado');

        await pumpPanel(tester, reactiveButtons());
        await tester.tap(find.text('Conectar y abrir RDP'));
        await tester.pumpAndSettle();

        expect(controller.splitTunnelActive, isTrue);
        final outlined = tester.widget<OutlinedButton>(
          find.ancestor(
            of: find.text('Desconectar túnel'),
            matching: find.bySubtype<OutlinedButton>(),
          ),
        );
        expect(outlined.onPressed, isNotNull);

        await tester.tap(find.text('Desconectar túnel'));
        await tester.pumpAndSettle();

        expect(controller.splitTunnelActive, isFalse);
        verify(() => mockRouteManager.disableSplitTunnel()).called(1);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('NetworkDiagnosticsView', () {
    testWidgets('shows scanned networks and hides the manual entry',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await initLoadedController();
        await pumpPanel(tester, const NetworkDiagnosticsView());

        expect(find.text('1. Conexión Wi-Fi'), findsOneWidget);
        expect(find.text('Contraseña Wi-Fi'), findsOneWidget);
        expect(find.text('Actualizar redes'), findsOneWidget);
        expect(find.text('Conectar Wi-Fi'), findsOneWidget);
        expect(find.text('Nombre de la red Wi-Fi'), findsNothing);

        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();

        expect(find.text('HUV_WIFI'), findsWidgets);
        expect(find.text('Invitados_HUV'), findsOneWidget);
        expect(find.text('Otra red…'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('surfaces scan errors and reveals the manual entry',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        stubStorageDefaults();
        // El escaneo falla desde el arranque, así que la lista queda vacía y
        // el error es visible junto al campo manual.
        when(() => mockWifiManager.scanNetworks())
            .thenThrow(const WifiConnectionException('nmcli no disponible'));
        when(() => mockWifiManager.getCurrentConnectionInfo()).thenAnswer(
          (_) async => const WifiConnectionInfo(
            ssid: 'HUV_WIFI',
            interfaceName: 'wlan0',
            gateway: '192.168.5.1',
          ),
        );
        await controller.init();
        await pumpPanel(tester, const NetworkDiagnosticsView());

        expect(
          find.textContaining('Error al buscar redes Wi-Fi'),
          findsOneWidget,
        );
        expect(find.text('Nombre de la red Wi-Fi'), findsOneWidget);

        await tester.tap(find.text('Actualizar redes'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Error al buscar redes Wi-Fi'),
          findsOneWidget,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('reveals the manual field when other network is chosen',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await initLoadedController();
        await pumpPanel(tester, const NetworkDiagnosticsView());

        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Otra red…').last);
        await tester.pumpAndSettle();

        expect(find.text('Nombre de la red Wi-Fi'), findsOneWidget);
        expect(controller.selectedWifiSsid, controller.manualWifiOption);

        await tester.enterText(
          find.byType(TextField).at(0),
          'Red_Medica',
        );
        await tester.pump();

        expect(controller.manualWifiCtrl.text, 'Red_Medica');
        expect(controller.selectedWifiSsid, controller.manualWifiOption);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('replaces the selector on platforms without native Wi-Fi',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await initLoadedController();
        await pumpPanel(tester, const NetworkDiagnosticsView());

        expect(
          find.textContaining(
            'la conexión Wi-Fi debe hacerse desde los ajustes del sistema',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('Consejo:'), findsOneWidget);
        expect(find.byType(DropdownButtonFormField<String>), findsNothing);
        expect(find.text('Contraseña Wi-Fi'), findsNothing);

        final refresh = tester.widget<OutlinedButton>(
          find.ancestor(
            of: find.text('Actualizar redes'),
            matching: find.bySubtype<OutlinedButton>(),
          ),
        );
        expect(refresh.onPressed, isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('expands the advanced options', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await initLoadedController();
        await pumpPanel(tester, const NetworkDiagnosticsView());

        expect(find.text('Puerta de enlace (Gateway)'), findsNothing);

        await tester.tap(find.text('Opciones avanzadas'));
        await tester.pumpAndSettle();

        expect(find.text('Puerta de enlace (Gateway)'), findsOneWidget);
        expect(find.text('Interfaz de red'), findsOneWidget);
        expect(
          find.text('Subredes del hospital (una por línea)'),
          findsOneWidget,
        );
        expect(find.text('Detectar red actual'), findsOneWidget);

        await tester.tap(find.text('Detectar red actual'));
        await tester.pumpAndSettle();

        expect(controller.currentWifiSsid, 'HUV_WIFI');
        expect(
          controller.logs.any((l) => l.contains('Red actual: HUV_WIFI')),
          isTrue,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('ServerSelectionPanel', () {
    testWidgets('lists the manual option and every hospital preset',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await initLoadedController();
        await pumpPanel(tester, const ServerSelectionPanel());

        expect(find.text('2. Escritorio remoto'), findsOneWidget);
        expect(
          find.textContaining('La app medirá respuesta TCP'),
          findsOneWidget,
        );

        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();

        expect(find.text('Manual'), findsWidgets);
        expect(
          find.text('Pediatría - serv_pediatrico.huv.gov.co:3389'),
          findsOneWidget,
        );
        expect(
          find.text('Urgencias - serv_urgencias.huv.gov.co:3389'),
          findsOneWidget,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('fills the RDP fields when a preset is selected',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await initLoadedController();
        controller.preferMostStableServer = true;
        await pumpPanel(tester, const ServerSelectionPanel());

        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester
            .tap(find.text('Urgencias - serv_urgencias.huv.gov.co:3389').last);
        await tester.pumpAndSettle();

        expect(controller.rdpHostCtrl.text, 'serv_urgencias.huv.gov.co');
        expect(controller.rdpPortCtrl.text, '3389');
        expect(controller.selectedServerPresetId, 'urgencias');
        expect(controller.preferMostStableServer, isFalse);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('warns when a preset is still pending configuration',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await initLoadedController();
        controller.serverPresets = [
          const ServerPreset(
            id: 'pendiente_x',
            label: 'Pendiente X',
            host: 'pendiente',
            port: 3389,
          ),
        ];
        await pumpPanel(tester, const ServerSelectionPanel());

        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Pendiente X - pendiente por configurar'));
        await tester.pumpAndSettle();

        expect(controller.guidanceIsError, isTrue);
        expect(controller.guidanceTitle, 'Servidor pendiente de configuración');
        expect(controller.selectedServerPresetId, 'pendiente_x');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('toggles automatic server selection', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await initLoadedController();
        await pumpPanel(tester, const ServerSelectionPanel());

        await tester.tap(find.byType(SwitchListTile));
        await tester.pump();

        expect(controller.preferMostStableServer, isTrue);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('diagnoses the best server on demand', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await initLoadedController();
        var calls = 0;
        when(() => mockNetworkDiagnostics.checkTcpPortDetailed(
              any(),
              any(),
            )).thenAnswer((_) async {
          calls++;
          return NetworkProbeResult(value: calls == 3 ? 5 : 40);
        });

        await pumpPanel(tester, const ServerSelectionPanel());
        await tester.tap(find.text('Diagnosticar mejor servidor'));
        await tester.pumpAndSettle();

        expect(controller.selectedServerPresetId, 'moviles');
        expect(controller.rdpHostCtrl.text, 'serv_moviles.huv.gov.co');
        expect(
          controller.logs.any((l) => l.contains('Urgencias')),
          isTrue,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('hides the RDP profile selector on Linux', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await initLoadedController();
        await pumpPanel(tester, const ServerSelectionPanel());

        expect(find.text('Perfil RDP'), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('offers RDP profiles on Windows', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await initLoadedController();
        await pumpPanel(tester, const ServerSelectionPanel());

        expect(find.text('Perfil RDP'), findsOneWidget);
        expect(find.text('Adaptativo'), findsOneWidget);

        await tester.tap(find.text('Perfil RDP'));
        await tester.pumpAndSettle();

        expect(find.text('Máxima estabilidad'), findsOneWidget);
        expect(find.text('Máxima velocidad'), findsOneWidget);
        await tester.tap(find.text('Máxima velocidad').last);
        await tester.pumpAndSettle();

        expect(controller.rdpProfile, 'speed');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
