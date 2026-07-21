//
//  Generated file. Do not edit.
//  (Manually extended with NetworkDiagnosticsPlugin)
//

import FlutterMacOS
import Foundation

import connectivity_plus
import url_launcher_macos

func RegisterGeneratedPlugins(registry: FlutterPluginRegistry) {
  ConnectivityPlusPlugin.register(with: registry.registrar(forPlugin: "ConnectivityPlusPlugin"))
  UrlLauncherPlugin.register(with: registry.registrar(forPlugin: "UrlLauncherPlugin"))
  NetworkDiagnosticsPlugin.register(with: registry.registrar(forPlugin: "NetworkDiagnosticsPlugin"))
}
