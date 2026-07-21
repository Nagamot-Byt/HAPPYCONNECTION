#include "network_diagnostics_plugin.h"

#include <windows.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <cstdlib>
#include <memory>
#include <sstream>
#include <string>
#include <vector>
#include <regex>

namespace medlink_connect {

// static
void NetworkDiagnosticsPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "com.medlinkconnect/network_diagnostics",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<NetworkDiagnosticsPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

NetworkDiagnosticsPlugin::NetworkDiagnosticsPlugin() = default;

NetworkDiagnosticsPlugin::~NetworkDiagnosticsPlugin() = default;

void NetworkDiagnosticsPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto& method_name = method_call.method_name();

  if (method_name == "flushDns") {
    // Windows: ipconfig /flushdns
    if (!IsElevated()) {
      result->Error("elevation_required",
                    "Elevation required: DNS flush needs Administrator privileges.",
                    nullptr);
      return;
    }
    auto [output, exit_code] = RunCommand("ipconfig /flushdns");
    auto ok = (exit_code == 0);
    result->Success(flutter::EncodableValue(ok));

  } else if (method_name == "clearNetworkCaches") {
    // Windows: arp -d * then netsh interface ip delete arpcache
    if (!IsElevated()) {
      result->Error("elevation_required",
                    "Elevation required: ARP cache clear needs Administrator privileges.",
                    nullptr);
      return;
    }
    RunCommand("arp -d *");
    auto [output, exit_code] = RunCommand("netsh interface ip delete arpcache");
    auto ok = (exit_code == 0);
    result->Success(flutter::EncodableValue(ok));

  } else if (method_name == "ping") {
    const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (!arguments) {
      result->Error("bad_arguments", "Expected a map with 'host', 'count', 'timeoutMs'.", nullptr);
      return;
    }

    std::string host = "8.8.8.8";
    int count = 4;
    int timeout_ms = 2000;

    auto host_it = arguments->find(flutter::EncodableValue("host"));
    if (host_it != arguments->end() && std::holds_alternative<std::string>(host_it->second)) {
      host = std::get<std::string>(host_it->second);
    }

    auto count_it = arguments->find(flutter::EncodableValue("count"));
    if (count_it != arguments->end() && std::holds_alternative<int>(count_it->second)) {
      count = std::get<int>(count_it->second);
    }

    auto to_it = arguments->find(flutter::EncodableValue("timeoutMs"));
    if (to_it != arguments->end() && std::holds_alternative<int>(to_it->second)) {
      timeout_ms = std::get<int>(to_it->second);
    }

    // Build command: ping -n {count} -w {timeout} {host}
    // Note: -w is per-packet timeout in ms
    std::ostringstream cmd;
    cmd << "ping -n " << count << " -w " << timeout_ms << " " << host;

    auto [output, exit_code] = RunCommand(cmd.str());

    if (exit_code != 0) {
      // ping returns non-zero when host is unreachable — not an error, just no connectivity
      result->Success(flutter::EncodableValue());  // null
      return;
    }

    // Parse average RTT from output
    // Look for: "Average = XXms"
    std::regex avg_re(R"(Average\s*=\s*(\d+)\s*ms)", std::regex::icase);
    std::smatch match;
    if (std::regex_search(output, match, avg_re)) {
      int avg = std::stoi(match[1].str());
      result->Success(flutter::EncodableValue(avg));
      return;
    }

    // Spanish Windows: "Media = XXms"
    std::regex media_re(R"(Media\s*=\s*(\d+)\s*ms)", std::regex::icase);
    if (std::regex_search(output, match, media_re)) {
      int avg = std::stoi(match[1].str());
      result->Success(flutter::EncodableValue(avg));
      return;
    }

    result->Success(flutter::EncodableValue());  // null — couldn't parse

  } else {
    result->NotImplemented();
  }
}

std::pair<std::string, int> NetworkDiagnosticsPlugin::RunCommand(
    const std::string& command) {
  // Use a pipe to capture output
  std::string full_cmd = "cmd.exe /c " + command + " 2>&1";

  HANDLE h_read, h_write;
  SECURITY_ATTRIBUTES sa = {sizeof(SECURITY_ATTRIBUTES), nullptr, TRUE};
  if (!CreatePipe(&h_read, &h_write, &sa, 0)) {
    return {"Failed to create pipe", 1};
  }

  SetHandleInformation(h_read, HANDLE_FLAG_INHERIT, 0);

  STARTUPINFOA si = {sizeof(STARTUPINFOA)};
  si.dwFlags = STARTF_USESTDHANDLES;
  si.hStdOutput = h_write;
  si.hStdError = h_write;

  PROCESS_INFORMATION pi = {};

  // Copy command for CreateProcess (it may modify the buffer)
  std::vector<char> cmd_buf(full_cmd.begin(), full_cmd.end());
  cmd_buf.push_back('\0');

  BOOL created = CreateProcessA(
      nullptr,            // lpApplicationName
      cmd_buf.data(),     // lpCommandLine
      nullptr,            // lpProcessAttributes
      nullptr,            // lpThreadAttributes
      TRUE,               // bInheritHandles
      CREATE_NO_WINDOW,   // dwCreationFlags
      nullptr,            // lpEnvironment
      nullptr,            // lpCurrentDirectory
      &si,
      &pi);

  CloseHandle(h_write);

  if (!created) {
    CloseHandle(h_read);
    return {"Failed to create process", 1};
  }

  // Read output
  std::string output;
  char buffer[4096];
  DWORD bytes_read;
  while (ReadFile(h_read, buffer, sizeof(buffer) - 1, &bytes_read, nullptr) &&
         bytes_read > 0) {
    buffer[bytes_read] = '\0';
    output += buffer;
  }
  CloseHandle(h_read);

  // Wait for process to finish (with timeout = 15 seconds)
  DWORD wait_result = WaitForSingleObject(pi.hProcess, 15000);
  DWORD exit_code = 1;

  if (wait_result == WAIT_OBJECT_0) {
    GetExitCodeProcess(pi.hProcess, &exit_code);
  } else {
    TerminateProcess(pi.hProcess, 1);
    exit_code = 1;
  }

  CloseHandle(pi.hProcess);
  CloseHandle(pi.hThread);

  return {output, static_cast<int>(exit_code)};
}

bool NetworkDiagnosticsPlugin::IsElevated() {
  BOOL is_elevated = FALSE;
  HANDLE token = nullptr;
  if (OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) {
    TOKEN_ELEVATION elevation;
    DWORD size = sizeof(TOKEN_ELEVATION);
    if (GetTokenInformation(token, TokenElevation, &elevation, size, &size)) {
      is_elevated = elevation.TokenIsElevated;
    }
    CloseHandle(token);
  }
  return is_elevated != FALSE;
}

}  // namespace medlink_connect
