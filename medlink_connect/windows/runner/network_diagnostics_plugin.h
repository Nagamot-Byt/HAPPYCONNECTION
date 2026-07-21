#pragma once

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>

namespace medlink_connect {

/// Windows implementation of the `com.medlinkconnect/network_diagnostics`
/// method channel.
///
/// Provides DNS flush, ARP cache clearing, and ICMP ping via native
/// Windows shell commands (`ipconfig`, `arp`, `netsh`, `ping`).
class NetworkDiagnosticsPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  NetworkDiagnosticsPlugin();

  virtual ~NetworkDiagnosticsPlugin();

 private:
  /// Called when a method call arrives on the channel.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  /// Run [command] via `cmd.exe /c` and return {stdout, exitCode}.
  /// On failure, returns non-zero exit code and stderr in stdout.
  std::pair<std::string, int> RunCommand(const std::string& command);

  /// Check whether we are running with Administrator privileges.
  bool IsElevated();
};

}  // namespace medlink_connect
