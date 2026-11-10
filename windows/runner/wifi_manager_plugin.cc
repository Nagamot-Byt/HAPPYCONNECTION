#include "wifi_manager_plugin.h"

#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <wlanapi.h>
#include <iphlpapi.h>
#include <netioapi.h>
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
#include <climits>
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

struct WifiSecurity {
  bool found = false;
  DOT11_AUTH_ALGORITHM auth = DOT11_AUTH_ALGO_RSNA_PSK;
  DOT11_CIPHER_ALGORITHM cipher = DOT11_CIPHER_ALGO_CCMP;
  bool is_open = false;
  bool is_psk = true;
  bool is_enterprise = false;
  bool is_wep = false;
};

static WifiSecurity DetectSecurity(HANDLE client, const GUID& interface_guid,
                                   const std::string& ssid) {
  WifiSecurity security;
  PWLAN_AVAILABLE_NETWORK_LIST networks = nullptr;
  if (WlanGetAvailableNetworkList(client, &interface_guid, 0, nullptr,
                                  &networks) != ERROR_SUCCESS) {
    return security;
  }

  for (DWORD i = 0; i < networks->dwNumberOfItems; ++i) {
    const auto& network = networks->Network[i];
    if (network.dot11Ssid.uSSIDLength == 0) continue;
    const std::string candidate(
        reinterpret_cast<const char*>(network.dot11Ssid.ucSSID),
        network.dot11Ssid.uSSIDLength);
    if (candidate != ssid) continue;

    security.found = true;
    security.auth = network.dot11DefaultAuthAlgorithm;
    security.cipher = network.dot11DefaultCipherAlgorithm;
    security.is_open =
        security.auth == DOT11_AUTH_ALGO_80211_OPEN &&
        security.cipher == DOT11_CIPHER_ALGO_NONE;
    security.is_wep =
        security.auth == DOT11_AUTH_ALGO_80211_OPEN &&
        security.cipher == DOT11_CIPHER_ALGO_WEP;
    security.is_enterprise =
        security.auth == DOT11_AUTH_ALGO_RSNA ||
        security.auth == DOT11_AUTH_ALGO_WPA ||
        security.auth == DOT11_AUTH_ALGO_WPA3 ||
        security.auth == DOT11_AUTH_ALGO_WPA3_ENT_192;
    security.is_psk =
        !security.is_enterprise && !security.is_open && !security.is_wep;
    break;
  }

  WlanFreeMemory(networks);
  return security;
}

static bool ProfileExists(HANDLE client, const GUID& interface_guid,
                          const std::wstring& ssid) {
  LPWSTR profile_xml = nullptr;
  DWORD flags = 0;
  DWORD reason = 0;
  const DWORD status =
      WlanGetProfile(client, &interface_guid, ssid.c_str(), nullptr,
                     &profile_xml, &flags, &reason);
  if (profile_xml) WlanFreeMemory(profile_xml);
  return status == ERROR_SUCCESS;
}

static const wchar_t* AuthName(DOT11_AUTH_ALGORITHM auth) {
  switch (auth) {
    case DOT11_AUTH_ALGO_WPA_PSK:
      return L"WPAPSK";
    case DOT11_AUTH_ALGO_WPA3_SAE:
      return L"WPA3SAE";
    case DOT11_AUTH_ALGO_WPA3_ENT_192:
      return L"WPA3ENT192";
    case DOT11_AUTH_ALGO_RSNA_PSK:
      return L"WPA2PSK";
    default:
      return L"WPA2PSK";
  }
}

static const wchar_t* CipherName(DOT11_CIPHER_ALGORITHM cipher,
                                 DOT11_AUTH_ALGORITHM auth) {
  if (auth == DOT11_AUTH_ALGO_WPA3_ENT_192) return L"GCMP256";
  if (auth == DOT11_AUTH_ALGO_WPA3_SAE) return L"GCMP256";
  if (auth == DOT11_AUTH_ALGO_WPA_PSK) return L"TKIP";
  if (cipher == DOT11_CIPHER_ALGO_GCMP_256) return L"GCMP256";
  if (cipher == DOT11_CIPHER_ALGO_GCMP) return L"GCMP";
  return L"AES";
}

static std::wstring BuildProfileXml(const std::wstring& ssid,
                                    const std::wstring& password,
                                    DOT11_AUTH_ALGORITHM auth,
                                    DOT11_CIPHER_ALGORITHM cipher) {
  const auto ssid_xml = XmlEscape(ssid);
  const auto password_xml = XmlEscape(password);
  const std::wstring auth_name = AuthName(auth);
  const std::wstring cipher_name = CipherName(cipher, auth);
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
      L"\n        <authentication>" + auth_name + L"</authentication>"
      L"\n        <encryption>" + cipher_name + L"</encryption>"
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

static std::wstring BuildOpenProfileXml(const std::wstring& ssid) {
  const auto ssid_xml = XmlEscape(ssid);
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
      L"\n        <authentication>open</authentication>"
      L"\n        <encryption>none</encryption>"
      L"\n        <useOneX>false</useOneX>"
      L"\n      </authEncryption>"
      L"\n    </security>"
      L"\n  </MSM>"
      L"\n</WLANProfile>\n";
}

static DWORD SetWlanProfile(HANDLE client, const GUID& interface_guid,
                            const std::wstring& profile_xml, bool overwrite,
                            DWORD* reason_code) {
  DWORD status = WlanSetProfile(client, &interface_guid, 0,
                                profile_xml.c_str(), nullptr, overwrite, nullptr,
                                reason_code);
  if (status == ERROR_ACCESS_DENIED) {
    status = WlanSetProfile(client, &interface_guid, WLAN_PROFILE_USER,
                            profile_xml.c_str(), nullptr, overwrite, nullptr,
                            reason_code);
  }
  return status;
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

static std::wstring InterfaceAliasFromGuid(const GUID& guid) {
  NET_LUID luid;
  if (ConvertInterfaceGuidToLuid(&guid, &luid) != NO_ERROR) return L"";
  wchar_t buffer[IF_MAX_STRING_SIZE + 1] = {0};
  if (ConvertInterfaceLuidToAlias(&luid, buffer, IF_MAX_STRING_SIZE + 1) !=
      NO_ERROR) {
    return L"";
  }
  return buffer;
}

static std::string DefaultGatewayForLuid(NET_LUID luid) {
  MIB_IPINTERFACE_ROW interface_row;
  InitializeIpInterfaceEntry(&interface_row);
  interface_row.InterfaceLuid = luid;
  interface_row.Family = AF_INET;
  if (GetIpInterfaceEntry(&interface_row) != NO_ERROR) return "";
  if (!interface_row.Connected || interface_row.DisableDefaultRoutes) return "";

  PMIB_IPFORWARD_TABLE2 table = nullptr;
  if (GetIpForwardTable2(AF_INET, &table) != NO_ERROR) return "";

  ULONG best_metric = ULONG_MAX;
  SOCKADDR_INET best_next_hop{};
  bool found = false;
  for (ULONG i = 0; i < table->NumEntries; ++i) {
    const auto& row = table->Table[i];
    if (row.InterfaceLuid.Value != luid.Value) continue;
    if (row.DestinationPrefix.PrefixLength != 0) continue;
    if (row.NextHop.Ipv4.sin_family != AF_INET) continue;
    if (row.NextHop.Ipv4.sin_addr.S_un.S_addr == 0) continue;
    if (!found || row.Metric < best_metric) {
      found = true;
      best_metric = row.Metric;
      best_next_hop = row.NextHop;
    }
  }
  FreeMibTable(table);

  if (!found) return "";
  char buffer[INET_ADDRSTRLEN] = {0};
  inet_ntop(AF_INET, &best_next_hop.Ipv4.sin_addr, buffer, INET_ADDRSTRLEN);
  return buffer;
}

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
      const std::wstring alias = InterfaceAliasFromGuid(pIfInfo->InterfaceGuid);
      out[EncodableValue("interfaceName")] = EncodableValue(WToU8(
          alias.empty() ? std::wstring(pIfInfo->strInterfaceDescription)
                        : alias));

      NET_LUID luid{};
      if (ConvertInterfaceGuidToLuid(&pIfInfo->InterfaceGuid, &luid) ==
          NO_ERROR) {
        out[EncodableValue("gateway")] =
            EncodableValue(DefaultGatewayForLuid(luid));
      }

      DWORD connectInfoSize = 0;
      PVOID rawConnectInfo = NULL;
      if (WlanQueryInterface(wlan.get(), &pIfInfo->InterfaceGuid,
                             wlan_intf_opcode_current_connection,
                             NULL, &connectInfoSize, &rawConnectInfo, NULL) == ERROR_SUCCESS) {
        auto* pConnectInfo =
            static_cast<PWLAN_CONNECTION_ATTRIBUTES>(rawConnectInfo);
        std::string ssid(
            (const char*)pConnectInfo->wlanAssociationAttributes.dot11Ssid.ucSSID,
            pConnectInfo->wlanAssociationAttributes.dot11Ssid.uSSIDLength);
        out[EncodableValue("ssid")] = EncodableValue(ssid);
        WlanFreeMemory(rawConnectInfo);
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
    for (DWORD i = 0; i < pIfList->dwNumberOfItems; ++i) {
      if (pIfList->InterfaceInfo[i].isState == wlan_interface_state_connected) {
        interfaceGuid = pIfList->InterfaceInfo[i].InterfaceGuid;
        break;
      }
    }
    WlanFreeMemory(pIfList);

    std::wstring profile_note;
    const std::wstring wssid = U8ToW(ssid);
    const WifiSecurity security =
        DetectSecurity(wlan.get(), interfaceGuid, ssid);
    const bool profile_exists =
        ProfileExists(wlan.get(), interfaceGuid, wssid);

    if (security.found && !security.is_psk && !security.is_open) {
      if (!profile_exists) {
        res->Error(
            "seguridad_no_soportada",
            security.is_enterprise
                ? "La red requiere autenticación empresarial (802.1X). "
                  "Configúrala desde Windows antes de conectar."
                : "El tipo de seguridad de esta red no se puede configurar "
                  "automáticamente.");
        return;
      }
      profile_note = L"Se usará el perfil de seguridad existente.";
    } else if (!password.empty()) {
      if (!security.found && profile_exists) {
        profile_note =
            L"No se pudo determinar la seguridad de la red; se usará el "
            L"perfil existente.";
      } else {
        const std::wstring profileXml = BuildProfileXml(
            wssid, U8ToW(password), security.auth, security.cipher);
        DWORD reasonCode = 0;
        const DWORD setProfileResult = SetWlanProfile(
            wlan.get(), interfaceGuid, profileXml, profile_exists,
            &reasonCode);
        if (setProfileResult != ERROR_SUCCESS) {
          profile_note =
              L"No se pudo actualizar el perfil Wi-Fi (código " +
              std::to_wstring(reasonCode) +
              L"). Se intentará conectar con perfil existente.";
        }
      }
    } else {
      if (security.found && !security.is_open) {
        if (!profile_exists) {
          res->Error(
              "password_requerida",
              "Esta red Wi-Fi requiere contraseña. Introdúcela para "
              "conectar.");
          return;
        }
        profile_note = L"Red protegida. Se usará el perfil guardado.";
      } else if (security.found && security.is_open) {
        if (!profile_exists) {
          DWORD reasonCodeOpen = 0;
          const DWORD openResult = SetWlanProfile(
              wlan.get(), interfaceGuid, BuildOpenProfileXml(wssid), false,
              &reasonCodeOpen);
          if (openResult != ERROR_SUCCESS &&
              openResult != ERROR_ALREADY_EXISTS) {
            profile_note =
                L"No se pudo crear el perfil de red abierta (código " +
                std::to_wstring(reasonCodeOpen) +
                L"). Se intentará conectar sin credenciales.";
          } else {
            profile_note =
                L"Red abierta. Se intentará conectar sin credenciales.";
          }
        } else {
          profile_note =
              L"Red abierta. Se usará el perfil existente sin "
              L"sobrescribirlo.";
        }
      } else {
        if (!profile_exists) {
          res->Error(
              "password_requerida",
              "No se pudo determinar la seguridad de esta red. Introduce la "
              "contraseña para continuar.");
          return;
        }
        profile_note =
            L"No se pudo determinar la seguridad de la red; se usará el "
            L"perfil existente.";
      }
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
      connParams.wlanConnectionMode = wlan_connection_mode_discovery_unsecure;
      connParams.strProfile = NULL;
      connParams.pDot11Ssid = &dot11Ssid;
      connParams.dwFlags = 0;
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
