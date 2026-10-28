#include "wifi_manager_plugin.h"

#include <windows.h>
#include <wlanapi.h>
#include <objbase.h>
#include <wtypes.h>

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <any>
#include <cstdio>
#include <regex>
#include <set>
#include <sstream>
#include <string>
#include <vector>
#include <thread>
#include <memory>

#include "utils.h"

#pragma comment(lib, "wlanapi.lib")
#pragma comment(lib, "ole32.lib")

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using MethodResultPtr = std::unique_ptr<flutter::MethodResult<EncodableValue>>;
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

static std::wstring XmlEscape(const std::wstring& s) {
  std::wstring out;
  out.reserve(s.size());
  for (wchar_t ch : s) {
    switch (ch) {
      case L'&': out += L"&amp;"; break;
      case L'<': out += L"&lt;"; break;
      case L'>': out += L"&gt;"; break;
      case L'"': out += L"&quot;"; break;
      case L'\'': out += L"&apos;"; break;
      default: out += ch; break;
    }
  }
  return out;
}

static std::wstring BuildWpa2ProfileXml(const std::wstring& ssid,
                                        const std::wstring& password) {
  const auto ssid_xml = XmlEscape(ssid);
  const auto password_xml = XmlEscape(password);
  return LR"(<?xml version="1.0"?>)"
      L"\n<WLANProfile xmlns=\"http://www.microsoft.com/networking/WLAN/profile/v1\">"
      L"\n  <name>" + ssid_xml + L"</name>"
      L"\n  <SSIDConfig>"
      L"\n    <SSID>"
      L"\n      <name>" + ssid_xml + L"</name>"
      L"\n    </SSID>"
      L"\n  </SSIDConfig>"
      L"\n  <connectionType>ESS</connectionType>"
      L"\n  <connectionMode>auto</connectionMode>"
      L"\n  <MSM>"
      L"\n    <security>"
      L"\n      <authEncryption>"
      L"\n        <authentication>WPA2PSK</authentication>"
      L"\n        <encryption>AES</encryption>"
      L"\n        <useOneX>false</useOneX>"
      L"\n      </authEncryption>"
      L"\n      <sharedKey>"
      L"\n        <keyType>passPhrase</keyType>"
      L"\n        <protected>false</protected>"
      L"\n        <keyMaterial>" + password_xml + L"</keyMaterial>"
      L"\n      </sharedKey>"
      L"\n    </security>"
      L"\n  </MSM>"
      L"\n</WLANProfile>\n";
}

// ------------------------------------------------------------------
// Wlan API Helpers
// ------------------------------------------------------------------
class WlanHandle {
 public:
  WlanHandle() {
    DWORD dwMaxClient = 2;
    DWORD dwCurVersion = 0;
    WlanOpenHandle(dwMaxClient, NULL, &dwCurVersion, &handle_);
  }
  ~WlanHandle() {
    if (handle_ != NULL) {
      WlanCloseHandle(handle_, NULL);
    }
  }
  HANDLE get() const { return handle_; }
  bool is_valid() const { return handle_ != NULL; }
 private:
  HANDLE handle_ = NULL;
};

// ------------------------------------------------------------------
//  GetCurrentInfo
// ------------------------------------------------------------------
static EncodableMap GetCurrentInfoMapNative() {
  EncodableMap out;
  out[EncodableValue("ssid")] = EncodableValue("");
  out[EncodableValue("interfaceName")] = EncodableValue("");
  out[EncodableValue("gateway")] = EncodableValue(""); // Retained for compatibility

  WlanHandle wlan;
  if (!wlan.is_valid()) return out;

  PWLAN_INTERFACE_INFO_LIST pIfList = NULL;
  if (WlanEnumInterfaces(wlan.get(), NULL, &pIfList) != ERROR_SUCCESS) {
    return out;
  }

  for (DWORD i = 0; i < pIfList->dwNumberOfItems; i++) {
    PWLAN_INTERFACE_INFO pIfInfo = (PWLAN_INTERFACE_INFO)&pIfList->InterfaceInfo[i];
    if (pIfInfo->isState == wlan_interface_state_connected) {
      out[EncodableValue("interfaceName")] = EncodableValue(WToU8(pIfInfo->strInterfaceDescription));

      DWORD connectInfoSize = 0;
      PWLAN_CONNECTION_ATTRIBUTES* pConnectInfo = NULL;
      if (WlanQueryInterface(wlan.get(), &pIfInfo->InterfaceGuid,
                             wlan_intf_opcode_current_connection,
                             NULL, &connectInfoSize, (PVOID*)&pConnectInfo, NULL) == ERROR_SUCCESS) {
        std::string ssid(
            (const char*)pConnectInfo->wlanAssociationAttributes.dot11Ssid.ucSSID,
            pConnectInfo->wlanAssociationAttributes.dot11Ssid.uSSIDLength);
        out[EncodableValue("ssid")] = EncodableValue(ssid);
        WlanFreeMemory(pConnectInfo);
      }
      break;
    }
  }
  
  if (pIfList != NULL) {
    WlanFreeMemory(pIfList);
  }

  return out;
}

// ------------------------------------------------------------------
//  ScanNetworks
// ------------------------------------------------------------------
static void HandleScanNetworks(MethodResultPtr result) {
  WlanHandle wlan;
  if (!wlan.is_valid()) {
    result->Error("wifi_no_disponible", "No se pudo iniciar la API de WLAN.");
    return;
  }

  PWLAN_INTERFACE_INFO_LIST pIfList = NULL;
  if (WlanEnumInterfaces(wlan.get(), NULL, &pIfList) != ERROR_SUCCESS) {
    result->Error("wifi_no_disponible", "No se encontraron interfaces Wi-Fi.");
    return;
  }

  std::set<std::string> seen;
  EncodableList out;

  for (DWORD i = 0; i < pIfList->dwNumberOfItems; i++) {
    PWLAN_INTERFACE_INFO pIfInfo = (PWLAN_INTERFACE_INFO)&pIfList->InterfaceInfo[i];
    PWLAN_AVAILABLE_NETWORK_LIST pBssList = NULL;
    
    // WlanGetAvailableNetworkList
    if (WlanGetAvailableNetworkList(wlan.get(), &pIfInfo->InterfaceGuid, 0, NULL, &pBssList) == ERROR_SUCCESS) {
      for (DWORD j = 0; j < pBssList->dwNumberOfItems; j++) {
        PWLAN_AVAILABLE_NETWORK pNetwork = &pBssList->Network[j];
        if (pNetwork->dot11Ssid.uSSIDLength > 0) {
          std::string ssid((const char*)pNetwork->dot11Ssid.ucSSID, pNetwork->dot11Ssid.uSSIDLength);
          if (seen.insert(ssid).second) {
            out.push_back(EncodableValue(ssid));
          }
        }
      }
      WlanFreeMemory(pBssList);
    }
  }

  if (pIfList != NULL) {
    WlanFreeMemory(pIfList);
  }

  result->Success(EncodableValue(out));
}

// ------------------------------------------------------------------
//  Connect
// ------------------------------------------------------------------
static void HandleConnect(const EncodableValue* args, MethodResultPtr result) {
  const auto* map = std::get_if<EncodableMap>(args);
  if (!map) {
    result->Error("argumento_invalido", "Se requiere un mapa de argumentos.");
    return;
  }

  std::string ssid;
  std::string password;
  for (const auto& [k, v] : *map) {
    const auto* key = std::get_if<std::string>(&k);
    if (!key) continue;
    if (*key == "ssid") {
      if (const auto* value = std::get_if<std::string>(&v)) ssid = *value;
    } else if (*key == "password") {
      if (const auto* value = std::get_if<std::string>(&v)) password = *value;
    }
  }

  if (ssid.empty()) {
    result->Error("argumento_invalido", "Debes seleccionar una red Wi-Fi.");
    return;
  }

  // Move operation to async thread to prevent UI freezing
  std::thread([ssid, password, res = std::move(result)]() mutable {
    WlanHandle wlan;
    if (!wlan.is_valid()) {
      res->Error("error_wifi", "No se pudo iniciar la API de WLAN.");
      return;
    }

    PWLAN_INTERFACE_INFO_LIST pIfList = NULL;
    if (WlanEnumInterfaces(wlan.get(), NULL, &pIfList) != ERROR_SUCCESS || pIfList->dwNumberOfItems == 0) {
      if (pIfList) WlanFreeMemory(pIfList);
      res->Error("error_wifi", "No hay interfaces Wi-Fi disponibles.");
      return;
    }

    GUID interfaceGuid = pIfList->InterfaceInfo[0].InterfaceGuid;
    WlanFreeMemory(pIfList);

    std::wstring profile_note;
    std::wstring wssid = U8ToW(ssid);

    if (!password.empty()) {
      std::wstring profileXml = BuildWpa2ProfileXml(wssid, U8ToW(password));
      DWORD reasonCode = 0;
      if (WlanSetProfile(wlan.get(), &interfaceGuid, 0, profileXml.c_str(), NULL, TRUE, NULL, &reasonCode) != ERROR_SUCCESS) {
        if (reasonCode == WLAN_REASON_CODE_PROFILE_ALREADY_EXISTS) {
          profile_note = L"Ya existía un perfil Wi-Fi para \"" + wssid + L"\". Se reutilizará el perfil guardado.";
        } else {
          profile_note = L"No se pudo actualizar el perfil Wi-Fi (código " + std::to_wstring(reasonCode) + L"). Se intentará conectar con perfil existente.";
        }
      }
    } else {
      // Red abierta: crear perfil abierto explícito si es posible
      std::wstring openXml = LR"(<?xml version="1.0"?>)"
          L"\n<WLANProfile xmlns=\"http://www.microsoft.com/networking/WLAN/profile/v1\">"
          L"\n  <name>" + XmlEscape(wssid) + L"</name>"
          L"\n  <SSIDConfig>"
          L"\n    <SSID>"
          L"\n      <name>" + XmlEscape(wssid) + L"</name>"
          L"\n    </SSID>"
          L"\n  </SSIDConfig>"
          L"\n  <connectionType>ESS</connectionType>"
          L"\n  <connectionMode>auto</connectionMode>"
          L"\n  <MSM>"
          L"\n    <security>"
          L"\n      <authEncryption>"
          L"\n        <authentication>open</authentication>"
          L"\n        <encryption>none</encryption>"
          L"\n        <useOneX>false</useOneX>"
          L"\n      </authEncryption>"
          L"\n    </security>"
          L"\n  </MSM>"
          L"\n</WLANProfile>\n";
      DWORD reasonCodeOpen = 0;
      WlanSetProfile(wlan.get(), &interfaceGuid, 0, openXml.c_str(), NULL, TRUE, NULL, &reasonCodeOpen);
      profile_note = L"Red abierta. Se intentará conectar sin credenciales.";
    }

    WLAN_CONNECTION_PARAMETERS connParams = {0};
    // Intentar primero con perfil guardado
    connParams.wlanConnectionMode = wlan_connection_mode_profile;
    connParams.strProfile = wssid.c_str();
    connParams.pDot11Ssid = NULL;
    connParams.pDesiredBssidList = NULL;
    connParams.dot11BssType = dot11_BSS_type_any;
    connParams.dwFlags = 0;

    DWORD connectResult = WlanConnect(wlan.get(), &interfaceGuid, &connParams, NULL);
    if (connectResult != ERROR_SUCCESS) {
      // Fallback: intentar con SSID directo (para redes abiertas/descubrimiento)
      DOT11_SSID dot11Ssid = {0};
      dot11Ssid.uSSIDLength = (ULONG)ssid.length();
      if (dot11Ssid.uSSIDLength > 32) dot11Ssid.uSSIDLength = 32;
      memcpy(dot11Ssid.ucSSID, ssid.c_str(), dot11Ssid.uSSIDLength);
      connParams.wlanConnectionMode = wlan_connection_mode_discovery_unmanaged;
      connParams.strProfile = NULL;
      connParams.pDot11Ssid = &dot11Ssid;
      connParams.dwFlags = WLAN_CONNECTION_HIDDEN_NETWORK;
      connectResult = WlanConnect(wlan.get(), &interfaceGuid, &connParams, NULL);
      if (connectResult != ERROR_SUCCESS) {
        res->Error("error_wifi", "No se pudo iniciar la conexión Wi-Fi. Error: " + std::to_string(connectResult));
        return;
      }
    }

    // Esperar más tiempo a que se establezca la conexión (DHCP/gateway)
    for (int i = 0; i < 12; ++i) {
      Sleep(1000);
      const auto current = GetCurrentInfoMapNative();
      const auto* current_ssid =
          std::get_if<std::string>(&current.at(EncodableValue("ssid")));
      if (current_ssid && *current_ssid == ssid) {
        const auto prefix = profile_note.empty() ? std::string() : WToU8(profile_note) + " ";
        res->Success(EncodableValue(prefix + "Conectado a la red Wi-Fi \"" + ssid + "\"."));
        return;
      }
    }

    const auto prefix = profile_note.empty() ? std::string() : WToU8(profile_note) + " ";
    res->Success(EncodableValue(prefix + "Solicitud de conexión enviada a la red Wi-Fi \"" + ssid +
        "\". La conexión puede tardar unos segundos."));
  }).detach();
}

// ------------------------------------------------------------------
//  Method call dispatcher
// ------------------------------------------------------------------
static void HandleMethodCall(
    const flutter::MethodCall<EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const auto& method = method_call.method_name();
  const auto* args = method_call.arguments();

  if (method == "scanNetworks") {
    HandleScanNetworks(std::move(result));
    return;
  }

  if (method == "connect") {
    HandleConnect(args, std::move(result));
    return;
  }

  if (method == "getCurrentInfo") {
    auto map = GetCurrentInfoMapNative();
    result->Success(EncodableValue(map));
    return;
  }

  result->NotImplemented();
}

}  // namespace

void WifiManagerPluginRegisterWithRegistrar(
    flutter::FlutterEngine* engine) {
  auto channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      engine->messenger(), "com.medlinkconnect/wifi_manager",
      &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(HandleMethodCall);
  static std::vector<MethodChannelPtr> s_channels;
  s_channels.push_back(std::move(channel));
}
