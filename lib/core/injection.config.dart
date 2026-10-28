// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:get_it/get_it.dart' as _i174;
import 'package:injectable/injectable.dart' as _i526;
import 'package:shared_preferences/shared_preferences.dart' as _i460;

import '../features/health_check/default_network_diagnostics.dart' as _i696;
import '../features/rdp_launcher/default_rdp_launcher.dart' as _i800;
import '../features/split_tunnel/default_route_manager.dart' as _i50;
import '../features/wifi/default_wifi_manager.dart' as _i147;
import 'connection_workflow_service.dart' as _i693;
import 'injection.dart' as _i464;
import 'network_diagnostics.dart' as _i705;
import 'rdp_launcher.dart' as _i302;
import 'route_manager.dart' as _i755;
import 'settings_storage.dart' as _i939;
import 'wifi_manager.dart' as _i651;

extension GetItInjectableX on _i174.GetIt {
// initializes the registration of main-scope dependencies inside of GetIt
  Future<_i174.GetIt> init({
    String? environment,
    _i526.EnvironmentFilter? environmentFilter,
  }) async {
    final gh = _i526.GetItHelper(
      this,
      environment,
      environmentFilter,
    );
    final appModule = _$AppModule();
    await gh.factoryAsync<_i460.SharedPreferences>(
      () => appModule.prefs,
      preResolve: true,
    );
    gh.lazySingleton<_i939.SettingsStorage>(
        () => _i939.SettingsStorage(gh<_i460.SharedPreferences>()));
    gh.lazySingleton<_i755.RouteManager>(() => _i50.DefaultRouteManager());
    gh.lazySingleton<_i705.NetworkDiagnostics>(
        () => _i696.DefaultNetworkDiagnostics());
    gh.lazySingleton<_i651.WifiManager>(() => _i147.DefaultWifiManager());
    gh.lazySingleton<_i302.RdpLauncher>(() => _i800.DefaultRdpLauncher());
    gh.lazySingleton<_i693.ConnectionWorkflowService>(
        () => _i693.ConnectionWorkflowService(
              gh<_i755.RouteManager>(),
              gh<_i705.NetworkDiagnostics>(),
              gh<_i302.RdpLauncher>(),
              wifiManager: gh<_i651.WifiManager>(),
            ));
    return this;
  }
}

class _$AppModule extends _i464.AppModule {}
