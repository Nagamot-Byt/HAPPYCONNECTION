//
//  Generated file. Do not edit.
//  (Manually extended with NetworkDiagnosticsPlugin)
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <connectivity_plus/connectivity_plus_windows_plugin.h>
#include <url_launcher_windows/url_launcher_windows.h>

#include "network_diagnostics_plugin.h"

void RegisterPlugins(flutter::PluginRegistry* registry) {
  ConnectivityPlusWindowsPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("ConnectivityPlusWindowsPlugin"));
  UrlLauncherWindowsRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("UrlLauncherWindows"));
  medlink_connect::NetworkDiagnosticsPlugin::RegisterWithRegistrar(
      registry->GetRegistrarForPlugin("NetworkDiagnosticsPlugin"));
}
