#include "rdp_launcher_plugin.h"

#include <windows.h>
#include <shellapi.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <stdlib.h>
#include <stdio.h>
#include <any>
#include <string>
#include <sstream>
#include <vector>
#include <thread>
#include <chrono>

#include "utils.h"

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using MethodChannelPtr =
    std::unique_ptr<flutter::MethodChannel<EncodableValue>>;

static std::wstring U8ToW(const std::string& s) { return Utf16FromUtf8(s); }
static std::string WToU8(const std::wstring& w) { return Utf8FromUtf16(w.c_str()); }

static EncodableValue ErrPair(const std::string& code,
                              const std::string& msg) {
  return flutter::CustomEncodableValue(std::make_pair(code, msg));
}

static bool DecodeErrPair(const flutter::CustomEncodableValue& err,
                          std::string* code,
                          std::string* msg) {
  try {
    const auto& pair =
        std::any_cast<const std::pair<std::string, std::string>&>(
            static_cast<const std::any&>(err));
    *code = pair.first;
    *msg = pair.second;
    return true;
  } catch (const std::bad_any_cast&) {
    *code = "error_interno";
    *msg = "No se pudo decodificar el error nativo.";
    return false;
  }
}

static bool FileExistsOnPath(const std::wstring& name) {
  DWORD len = SearchPathW(NULL, name.c_str(), L".exe", 0, NULL, NULL);
  if (len == 0) {
    len = SearchPathW(NULL, name.c_str(), NULL, 0, NULL, NULL);
  }
  return len > 0;
}

static bool UriSchemeRegistered(const std::wstring& scheme) {
  HKEY hKey = NULL;
  std::wstring subkey = L"Software\\Classes\\" + scheme;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, subkey.c_str(), 0, KEY_READ, &hKey)
      != ERROR_SUCCESS) {
    if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, subkey.c_str(), 0, KEY_READ, &hKey)
        != ERROR_SUCCESS) {
      return false;
    }
  }
  RegCloseKey(hKey);
  return true;
}

struct LaunchStatus {
  bool started = false;
  DWORD win_error = ERROR_SUCCESS;
  HANDLE process = nullptr;
};

static void BestEffortDeleteFile(const std::wstring& path) {
  if (!path.empty()) {
    DeleteFileW(path.c_str());
  }
}

static void CleanupStaleRdpFiles(const std::wstring& temp_dir) {
  const std::wstring pattern = temp_dir + L"medlink_connect_*.rdp";
  WIN32_FIND_DATAW data{};
  HANDLE find = FindFirstFileW(pattern.c_str(), &data);
  if (find == INVALID_HANDLE_VALUE) return;
  do {
    if ((data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0) {
      const std::wstring full_path = temp_dir + data.cFileName;
      DeleteFileW(full_path.c_str());
    }
  } while (FindNextFileW(find, &data));
  FindClose(find);
}

static void DeleteFileAfterProcessExit(HANDLE process,
                                       const std::wstring& path) {
  std::thread([process, path]() {
    if (process != nullptr) {
      WaitForSingleObject(process, INFINITE);
    }
    for (int attempt = 0; attempt < 20; ++attempt) {
      if (DeleteFileW(path.c_str())) break;
      std::this_thread::sleep_for(std::chrono::milliseconds(250));
    }
    if (process != nullptr) {
      CloseHandle(process);
    }
  }).detach();
}

static LaunchStatus LaunchProcess(const std::wstring& command_line) {
  LaunchStatus status;
  STARTUPINFOW si{};
  si.cb = sizeof(STARTUPINFOW);

  PROCESS_INFORMATION pi{};
  std::vector<wchar_t> mutable_cmd(command_line.begin(), command_line.end());
  mutable_cmd.push_back(L'\0');

  const BOOL created = CreateProcessW(
      NULL, mutable_cmd.data(), NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi);
  if (!created) {
    status.win_error = GetLastError();
    return status;
  }

  status.started = true;
  status.process = pi.hProcess;
  CloseHandle(pi.hThread);
  return status;
}

enum class RdpProfile {
  kAdaptive,
  kStable,
  kSpeed,
};

static RdpProfile ParseRdpProfile(const std::string& value) {
  if (value == "stable") return RdpProfile::kStable;
  if (value == "speed") return RdpProfile::kSpeed;
  return RdpProfile::kAdaptive;
}

static bool IsSafeRdpValue(const std::wstring& value) {
  for (wchar_t c : value) {
    if (c == L'\r' || c == L'\n' || c == L'\0') return false;
  }
  return true;
}

static bool WriteOptimizedRdpFile(const std::wstring& path,
                                  const std::wstring& host,
                                  int port,
                                  const std::wstring& username,
                                  const std::wstring& domain,
                                  RdpProfile profile,
                                  int measured_latency_ms) {
  const bool high_latency =
      measured_latency_ms >= 0 && measured_latency_ms >= 120;
  const bool stable_mode =
      profile == RdpProfile::kStable ||
      (profile == RdpProfile::kAdaptive && high_latency);
  const bool speed_mode = profile == RdpProfile::kSpeed;
  const int session_bpp = (stable_mode || speed_mode) ? 16 : 24;
  const int connection_type = speed_mode ? 1 : (stable_mode ? 2 : 6);
  const int autoreconnect_retries = stable_mode ? 12 : 8;

  std::wstringstream contents;
  contents << L"full address:s:" << host << L":" << port << L"\r\n";
  if (!domain.empty()) {
    contents << L"domain:s:" << domain << L"\r\n";
  }
  if (!username.empty()) {
    if (!domain.empty()) {
      contents << L"username:s:" << domain << L"\\" << username << L"\r\n";
    } else {
      contents << L"username:s:" << username << L"\r\n";
    }
  }
  contents << L"prompt for credentials:i:1\r\n";
  contents << L"promptcredentialonce:i:0\r\n";
  contents << L"enablecredsspsupport:i:1\r\n";
  contents << L"authentication level:i:2\r\n";
  contents << L"autoreconnection enabled:i:1\r\n";
  contents << L"autoreconnect max retries:i:" << autoreconnect_retries << L"\r\n";
  contents << L"compression:i:1\r\n";
  contents << L"bitmapcachepersistenable:i:1\r\n";
  contents << L"networkautodetect:i:1\r\n";
  contents << L"bandwidthautodetect:i:1\r\n";
  contents << L"connection type:i:" << connection_type << L"\r\n";
  contents << L"session bpp:i:" << session_bpp << L"\r\n";
  contents << L"audiomode:i:2\r\n";
  contents << L"audiocapturemode:i:0\r\n";
  contents << L"redirectprinters:i:0\r\n";
  contents << L"redirectcomports:i:0\r\n";
  contents << L"redirectsmartcards:i:0\r\n";
  contents << L"redirectclipboard:i:1\r\n";
  contents << L"redirectwebauthn:i:0\r\n";
  contents << L"drivestoredirect:s:\r\n";
  contents << L"devicestoredirect:s:\r\n";
  contents << L"camerastoredirect:s:\r\n";
  contents << L"disable wallpaper:i:1\r\n";
  contents << L"disable full window drag:i:1\r\n";
  contents << L"disable menu anims:i:1\r\n";
  contents << L"disable themes:i:1\r\n";
  contents << L"allow font smoothing:i:0\r\n";
  contents << L"allow desktop composition:i:0\r\n";
  contents << L"administrative session:i:0\r\n";
  contents << L"use multimon:i:0\r\n";
  contents << L"displayconnectionbar:i:1\r\n";
  contents << L"smart sizing:i:0\r\n";
  contents << L"screen mode id:i:2\r\n";

  std::string content_u8 = WToU8(contents.str());
  FILE* f = nullptr;
  const errno_t open_err = _wfopen_s(&f, path.c_str(), L"wb");
  if (open_err != 0 || f == nullptr) {
    return false;
  }

  const size_t written = fwrite(content_u8.data(), 1, content_u8.size(), f);
  const int close_result = fclose(f);
  return written == content_u8.size() && close_result == 0;
}

// ------------------------------------------------------------------
//  preLaunch
// ------------------------------------------------------------------
static std::unique_ptr<EncodableValue> HandlePreLaunch() {
  if (UriSchemeRegistered(L"rdp") || UriSchemeRegistered(L"ms-rd-web")) {
    return std::make_unique<EncodableValue>(true);
  }
  if (FileExistsOnPath(L"mstsc")) {
    return std::make_unique<EncodableValue>(true);
  }
  return std::make_unique<EncodableValue>(ErrPair(
      "sin_manejador_rdp",
      "No se encontró un manejador para rdp:// ni ms-rd-web://"));
}

// ------------------------------------------------------------------
//  isRdpClientAvailable
// ------------------------------------------------------------------
static std::unique_ptr<EncodableValue> HandleIsAvailable() {
  if (FileExistsOnPath(L"mstsc")) return std::make_unique<EncodableValue>(true);
  if (FileExistsOnPath(L"RemoteDesktop"))
    return std::make_unique<EncodableValue>(true);
  if (UriSchemeRegistered(L"rdp"))
    return std::make_unique<EncodableValue>(true);
  if (UriSchemeRegistered(L"ms-rd-web"))
    return std::make_unique<EncodableValue>(true);
  return std::make_unique<EncodableValue>(false);
}

// ------------------------------------------------------------------
//  Percent encoder for URI components (RFC 3986, UTF-8 bytes)
// ------------------------------------------------------------------
static std::wstring PercentEncode(const std::wstring& input) {
  static const wchar_t kHex[] = L"0123456789ABCDEF";
  std::wstring out;
  out.reserve(input.size());
  std::wstring u8_as_ws;
  for (wchar_t c : input) {
    if ((c >= L'A' && c <= L'Z') || (c >= L'a' && c <= L'z') ||
        (c >= L'0' && c <= L'9') || c == L'-' || c == L'_' ||
        c == L'.' || c == L'~') {
      out.push_back(c);
    } else {
      out.push_back(L'%');
      std::string u8 = WToU8(std::wstring(1, c));
      for (unsigned char b : u8) {
        out.push_back(kHex[(b >> 4) & 0xF]);
        out.push_back(kHex[b & 0xF]);
      }
    }
  }
  return out;
}

// ------------------------------------------------------------------
//  launchRdp
// ------------------------------------------------------------------
static std::unique_ptr<EncodableValue> HandleLaunchRdp(
    const EncodableValue* args) {
  const auto* map = std::get_if<EncodableMap>(args);
  if (!map) {
    return std::make_unique<EncodableValue>(ErrPair(
        "argumento_invalido", "Se requiere un mapa de argumentos"));
  }

  std::string host_u8;
  int port = 3389;
  std::string username_u8;
  std::string domain_u8;
  std::string profile_u8 = "adaptive";
  bool use_webfeed = false;
  int measured_latency_ms = -1;

  for (const auto& [k, v] : *map) {
    const auto* ks = std::get_if<std::string>(&k);
    if (!ks) continue;
    if (*ks == "host") {
      if (auto* s = std::get_if<std::string>(&v)) host_u8 = *s;
    } else if (*ks == "port") {
      if (auto* i = std::get_if<int>(&v)) port = *i;
      else if (auto* s = std::get_if<std::string>(&v))
        port = atoi(s->c_str());
    } else if (*ks == "username") {
      if (auto* s = std::get_if<std::string>(&v)) username_u8 = *s;
    } else if (*ks == "domain") {
      if (auto* s = std::get_if<std::string>(&v)) domain_u8 = *s;
    } else if (*ks == "useWebFeed") {
      if (auto* b = std::get_if<bool>(&v)) use_webfeed = *b;
    } else if (*ks == "profile") {
      if (auto* s = std::get_if<std::string>(&v)) profile_u8 = *s;
    } else if (*ks == "measuredLatencyMs") {
      if (auto* i = std::get_if<int>(&v)) measured_latency_ms = *i;
    }
  }

  if (host_u8.empty()) {
    return std::make_unique<EncodableValue>(ErrPair(
        "argumento_invalido", "Falta el parámetro 'host'"));
  }
  if (port <= 0 || port > 65535) {
    return std::make_unique<EncodableValue>(ErrPair(
        "argumento_invalido", "Puerto RDP inválido"));
  }
  if (!IsSafeRdpValue(U8ToW(host_u8)) ||
      !IsSafeRdpValue(U8ToW(username_u8)) ||
      !IsSafeRdpValue(U8ToW(domain_u8))) {
    return std::make_unique<EncodableValue>(ErrPair(
        "argumento_invalido",
        "El host, usuario o dominio contiene caracteres no permitidos."));
  }

  std::wstring uri;
  if (use_webfeed) {
    uri = L"ms-rd-web://" + PercentEncode(U8ToW(host_u8));
  } else {
    uri = L"rdp://";
    std::wstring authority;
    std::string user_info_u8;
    if (!domain_u8.empty()) user_info_u8 += domain_u8 + "\\";
    if (!username_u8.empty()) user_info_u8 += username_u8;
    if (!user_info_u8.empty()) {
      authority += PercentEncode(U8ToW(user_info_u8)) + L"@";
    }
    authority += PercentEncode(U8ToW(host_u8)) + L":" +
                 std::to_wstring(port);
    uri += authority;
  }

  if (!use_webfeed) {
    if (FileExistsOnPath(L"mstsc")) {
      wchar_t tmp_path[MAX_PATH + 1]{};
      const DWORD len = GetTempPathW(MAX_PATH, tmp_path);
      if (len > 0) {
        CleanupStaleRdpFiles(std::wstring(tmp_path));
        const std::wstring rdp_file =
            std::wstring(tmp_path) + L"medlink_connect_" +
            std::to_wstring(GetCurrentProcessId()) + L"_" +
            std::to_wstring(GetTickCount64()) + L".rdp";
        const auto profile = ParseRdpProfile(profile_u8);
        const bool wrote_file =
            WriteOptimizedRdpFile(rdp_file, U8ToW(host_u8), port,
                                  U8ToW(username_u8), U8ToW(domain_u8),
                                  profile, measured_latency_ms);
        if (wrote_file) {
          const std::wstring command_line =
              L"mstsc.exe \"" + rdp_file + L"\" /public";
          const auto launch = LaunchProcess(command_line);
          if (launch.started) {
            DeleteFileAfterProcessExit(launch.process, rdp_file);
            return std::make_unique<EncodableValue>(
                "Conexión RDP lanzada a " + host_u8 + ":" +
                std::to_string(port) + " (perfil " + profile_u8 + ").");
          }
          BestEffortDeleteFile(rdp_file);
          const std::string msg =
              "No se pudo iniciar mstsc con el perfil optimizado. Código " +
              std::to_string(static_cast<int>(launch.win_error));
          return std::make_unique<EncodableValue>(
              ErrPair("lanzamiento_fallido", msg));
        }
        BestEffortDeleteFile(rdp_file);

        const std::wstring mstsc_args =
            L"mstsc.exe /v:" + U8ToW(host_u8) + L":" + std::to_wstring(port) + L" /public";
        const auto launch = LaunchProcess(mstsc_args);
        if (launch.started) {
          if (launch.process != nullptr) CloseHandle(launch.process);
          return std::make_unique<EncodableValue>(
              "Conexión RDP lanzada a " + host_u8 + ":" +
              std::to_string(port) + " (mstsc).");
        }
        const std::string msg =
            "No se pudo iniciar mstsc.exe. Código " +
            std::to_string(static_cast<int>(launch.win_error));
        return std::make_unique<EncodableValue>(
            ErrPair("lanzamiento_fallido", msg));
    }
  }

  HINSTANCE hInst = ShellExecuteW(
      NULL, L"open", uri.c_str(), NULL, NULL, SW_SHOWNORMAL);
  const intptr_t hi_val = (intptr_t)hInst;
  if (hi_val > 32) {
    return std::make_unique<EncodableValue>(
        "Conexión RDP lanzada a " + host_u8 + ":" + std::to_string(port) +
        " correctamente.");
  }

  const std::string msg =
      "No se pudo lanzar el cliente RDP. El manejador URI devolvió código " +
      std::to_string((int)hi_val);
  return std::make_unique<EncodableValue>(
      ErrPair("lanzamiento_fallido", msg));
}

// ------------------------------------------------------------------
//  Dispatcher
// ------------------------------------------------------------------
static void HandleMethodCall(
    const flutter::MethodCall<EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const auto& method = method_call.method_name();
  const auto* args = method_call.arguments();

  std::unique_ptr<EncodableValue> r;
  bool handled = true;

  if (method == "preLaunch") {
    r = HandlePreLaunch();
  } else if (method == "isRdpClientAvailable") {
    r = HandleIsAvailable();
  } else if (method == "launchRdp") {
    r = HandleLaunchRdp(args);
  } else {
    handled = false;
  }

  if (!handled) {
    result->NotImplemented();
    return;
  }
  if (auto* err = std::get_if<flutter::CustomEncodableValue>(r.get())) {
    std::string err_code, err_msg;
    DecodeErrPair(*err, &err_code, &err_msg);
    result->Error(err_code, err_msg);
    return;
  }
  if (auto* b = std::get_if<bool>(r.get())) {
    result->Success(EncodableValue(*b));
    return;
  }
  result->Success(*r);
}

}  // namespace

void RdpLauncherPluginRegisterWithRegistrar(
    flutter::FlutterEngine* engine) {
  auto channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      engine->messenger(), "com.medlinkconnect/rdp_launcher",
      &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(HandleMethodCall);
  static std::vector<MethodChannelPtr> s_channels;
  s_channels.push_back(std::move(channel));
}
