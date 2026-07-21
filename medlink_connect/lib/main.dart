import 'package:flutter/material.dart';
import 'package:medlink_connect/core/app_theme.dart';
import 'package:medlink_connect/features/health_check/default_network_diagnostics.dart';
import 'package:medlink_connect/features/rdp_launcher/default_rdp_launcher.dart';
import 'package:medlink_connect/features/split_tunnel/default_route_manager.dart';
import 'package:medlink_connect/features/ui/home_screen.dart';

/// The root widget for MedLink Connect.
///
/// Exposed as a named class so that widget tests can instantiate it
/// directly without going through [main].
class MedLinkConnectApp extends StatelessWidget {
  const MedLinkConnectApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MedLink Connect',
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      home: HomeScreen(
        networkDiagnostics: DefaultNetworkDiagnostics(),
        routeManager: DefaultRouteManager(),
        rdpLauncher: DefaultRdpLauncher(),
      ),
    );
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MedLinkConnectApp());
}
