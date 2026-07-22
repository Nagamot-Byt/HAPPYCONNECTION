import 'package:flutter/material.dart';
import 'package:medlink_connect/core/app_theme.dart';
import 'package:medlink_connect/features/health_check/default_network_diagnostics.dart';
import 'package:medlink_connect/features/rdp_launcher/default_rdp_launcher.dart';
import 'package:medlink_connect/features/split_tunnel/default_route_manager.dart';
import 'package:medlink_connect/features/ui/home_screen.dart';
import 'package:medlink_connect/features/ui/profiles_screen.dart';
import 'package:medlink_connect/features/ui/settings_screen.dart';

/// The root widget for MedLink Connect.
///
/// Exposed as a named class so that widget tests can instantiate it
/// directly without going through [main].
class MedLinkConnectApp extends StatelessWidget {
  MedLinkConnectApp({super.key}) : _rdpLauncher = DefaultRdpLauncher();

  final DefaultRdpLauncher _rdpLauncher;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MedLink Connect',
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/':
            return MaterialPageRoute(
              builder: (_) => HomeScreen(
                networkDiagnostics: DefaultNetworkDiagnostics(),
                routeManager: DefaultRouteManager(),
                rdpLauncher: _rdpLauncher,
              ),
            );
          case '/settings':
            return MaterialPageRoute(
              builder: (_) => const SettingsScreen(),
            );
          case '/profiles':
            return MaterialPageRoute(
              builder: (_) => ProfilesScreen(rdpLauncher: _rdpLauncher),
            );
          default:
            return MaterialPageRoute(
              builder: (_) => HomeScreen(
                networkDiagnostics: DefaultNetworkDiagnostics(),
                routeManager: DefaultRouteManager(),
                rdpLauncher: _rdpLauncher,
              ),
            );
        }
      },
    );
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MedLinkConnectApp());
}
