#include "route_manager_plugin.h"

#include <windows.h>
#include <iphlpapi.h>
#include <winsock2.h>
#include <ws2tcpip.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <stdlib.h>
#include <any>
#include <string>
#include <sstream>
#include <vector>
#include <mutex>
#include <algorithm>
#include <map>

#include "utils.h"

#pragma comment(lib, "iphlpapi.lib")
#pragma comment(lib, "ws2_32.lib")

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using MethodChannelPtr =
    std::unique_ptr<flutter::MethodChannel<EncodableValue>>;

struct TrackedRoute {
  std::wstring dest_cidr;
  std::wstring gateway;
  std::wstring iface;
  NET_LUID luid;
};

static std::mutex g_routes_mutex;
static std::vector<TrackedRoute> g_tracked_routes;

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

#include <ws2tcpip.h>

static bool ParseIPv4(const std::wstring& ip_str, SOCKADDR_INET& addr) {
  addr.Ipv4.sin_family = AF_INET;
  return InetPtonW(AF_INET, ip_str.c_str(), &addr.Ipv4.sin_addr) == 1;
}

static bool ParseCIDR(const std::wstring& cidr_str, SOCKADDR_INET& addr, UINT8& prefix) {
  auto pos = cidr_str.find(L'/');
  if (pos == std::wstring::npos) {
    prefix = 32;
    return ParseIPv4(cidr_str, addr);
  }
  std::wstring ip = cidr_str.substr(0, pos);
  try {
    int p = std::stoi(cidr_str.substr(pos + 1));
    if (p < 0 || p > 32) return false;
    prefix = static_cast<UINT8>(p);
  } catch (...) {
    return false;
  }
  return ParseIPv4(ip, addr);
}


static bool GetInterfaceLuid(const std::wstring& iface_alias, NET_LUID& luid) {
  return ConvertInterfaceAliasToLuid(iface_alias.c_str(), &luid) == NO_ERROR;
}

static bool RouteExists(const std::wstring& dest_cidr,
                        const std::wstring& gw,
                        const std::wstring& iface) {
  NET_LUID luid;
  bool has_luid = GetInterfaceLuid(iface, luid);

  SOCKADDR_INET dest_addr{}, gw_addr{};
  UINT8 prefix;
  if (!ParseCIDR(dest_cidr, dest_addr, prefix)) return false;
  bool has_gw = ParseIPv4(gw, gw_addr);

  PMIB_IPFORWARD_TABLE2 table = nullptr;
  if (GetIpForwardTable2(AF_INET, &table) != NO_ERROR) return false;

  bool found = false;
  for (ULONG i = 0; i < table->NumEntries; ++i) {
    const auto& row = table->Table[i];
    if (row.DestinationPrefix.PrefixLength != prefix) continue;
    if (row.DestinationPrefix.Prefix.Ipv4.sin_addr.S_un.S_addr != dest_addr.Ipv4.sin_addr.S_un.S_addr) continue;
    // Aceptar si existe ruta hacia ese destino por la misma interfaz O mismo gateway
    bool same_iface = has_luid && row.InterfaceLuid.Value == luid.Value;
    bool same_gw = has_gw && row.NextHop.Ipv4.sin_family == AF_INET &&
                   row.NextHop.Ipv4.sin_addr.S_un.S_addr == gw_addr.Ipv4.sin_addr.S_un.S_addr;
    if (same_iface || same_gw) {
      found = true;
      break;
    }
  }
  FreeMibTable(table);
  return found;
}

static DWORD AddRouteNative(const std::wstring& dest_cidr,
                            const std::wstring& gw,
                            const std::wstring& iface_alias) {
  MIB_IPFORWARD_ROW2 row;
  InitializeIpForwardEntry(&row);

  if (!GetInterfaceLuid(iface_alias, row.InterfaceLuid)) return ERROR_NOT_FOUND;

  UINT8 prefix;
  if (!ParseCIDR(dest_cidr, row.DestinationPrefix.Prefix, prefix)) return ERROR_INVALID_PARAMETER;
  row.DestinationPrefix.PrefixLength = prefix;

  if (!ParseIPv4(gw, row.NextHop)) return ERROR_INVALID_PARAMETER;
  row.NextHop.Ipv4.sin_family = AF_INET;
  
  // Dejar métrica automática para evitar conflictos con ruta por defecto
  row.Metric = 0;
  row.SitePrefixLength = 0;

  return CreateIpForwardEntry2(&row);
}

static DWORD RemoveRouteNative(const std::wstring& dest_cidr) {
  SOCKADDR_INET dest_addr{};
  UINT8 prefix;
  if (!ParseCIDR(dest_cidr, dest_addr, prefix)) return ERROR_INVALID_PARAMETER;

  PMIB_IPFORWARD_TABLE2 table = nullptr;
  if (GetIpForwardTable2(AF_INET, &table) != NO_ERROR) return ERROR_NOT_FOUND;

  DWORD last_err = ERROR_NOT_FOUND;
  for (ULONG i = 0; i < table->NumEntries; ++i) {
    auto& row = table->Table[i];
    if (row.DestinationPrefix.PrefixLength == prefix &&
        row.DestinationPrefix.Prefix.Ipv4.sin_addr.S_un.S_addr == dest_addr.Ipv4.sin_addr.S_un.S_addr) {
      // Solo eliminar rutas con next-hop (no ruta directa/connectada)
      if (row.NextHop.Ipv4.sin_family == AF_INET && row.NextHop.Ipv4.sin_addr.S_un.S_addr != 0) {
        last_err = DeleteIpForwardEntry2(&row);
      }
    }
  }
  FreeMibTable(table);
  return last_err;
}

// ------------------------------------------------------------------
//  addRoute
// ------------------------------------------------------------------
static std::unique_ptr<EncodableValue> HandleAddRoute(
    const std::string& dest, const std::string& gw,
    const std::string& iface) {
  if (dest.empty() || gw.empty() || iface.empty()) {
    return std::make_unique<EncodableValue>(ErrPair(
        "argumento_invalido",
        "Faltan parámetros: destinationCidr, gateway, interfaceName"));
  }
  if (!IsElevated()) {
    return std::make_unique<EncodableValue>(ErrPair(
        "permiso_denegado",
        "Se requieren privilegios de Administrador"));
  }

  auto wdest = U8ToW(dest);
  auto wgw = U8ToW(gw);
  auto wiface = U8ToW(iface);

  if (RouteExists(wdest, wgw, wiface)) {
    return std::make_unique<EncodableValue>(
        "Ruta " + dest + " ya existe para la interfaz indicada.");
  }

  const DWORD status = AddRouteNative(wdest, wgw, wiface);
  if (status != NO_ERROR) {
    std::string msg = "Error al agregar ruta " + dest + ": código " + std::to_string(status);
    return std::make_unique<EncodableValue>(
        ErrPair("error_comando", msg));
  }

  return std::make_unique<EncodableValue>(
      "Ruta " + dest + " agregada exitosamente.");
}

// ------------------------------------------------------------------
//  removeRoute
// ------------------------------------------------------------------
static std::unique_ptr<EncodableValue> HandleRemoveRoute(
    const std::string& dest) {
  if (dest.empty()) {
    return std::make_unique<EncodableValue>(ErrPair(
        "argumento_invalido", "Falta destinationCidr"));
  }
  if (!IsElevated()) {
    return std::make_unique<EncodableValue>(ErrPair(
        "permiso_denegado",
        "Se requieren privilegios de Administrador"));
  }

  auto wdest = U8ToW(dest);
  const DWORD status = RemoveRouteNative(wdest);
  
  if (status != NO_ERROR && status != ERROR_NOT_FOUND) {
    std::string msg = "Error al eliminar ruta " + dest + ": código " + std::to_string(status);
    return std::make_unique<EncodableValue>(
        ErrPair("error_comando", msg));
  }
  return std::make_unique<EncodableValue>("Ruta " + dest + " eliminada.");
}

// ------------------------------------------------------------------
//  enableSplitTunnel
// ------------------------------------------------------------------
static std::unique_ptr<EncodableValue> HandleEnableSplitTunnel(
    const EncodableValue* args) {
  const auto* map = std::get_if<EncodableMap>(args);
  if (!map) {
    return std::make_unique<EncodableValue>(ErrPair(
        "argumento_invalido", "Se requiere un mapa de argumentos"));
  }

  const EncodableValue* subnets_val = nullptr;
  const EncodableValue* gw_val = nullptr;
  const EncodableValue* iface_val = nullptr;
  for (const auto& [k, v] : *map) {
    if (const auto* ks = std::get_if<std::string>(&k)) {
      if (*ks == "hospitalSubnets") subnets_val = &v;
      else if (*ks == "gateway") gw_val = &v;
      else if (*ks == "interfaceName") iface_val = &v;
    }
  }
  const auto* subnets_list = subnets_val ?
      std::get_if<EncodableList>(subnets_val) : nullptr;
  const auto* gw_str = gw_val ? std::get_if<std::string>(gw_val) : nullptr;
  const auto* iface_str = iface_val ?
      std::get_if<std::string>(iface_val) : nullptr;

  if (!subnets_list || !gw_str || !iface_str) {
    return std::make_unique<EncodableValue>(ErrPair(
        "argumento_invalido",
        "Se requieren hospitalSubnets (lista), gateway, interfaceName"));
  }
  const bool is_elevated = IsElevated();
  if (!is_elevated) {
    return std::make_unique<EncodableValue>(ErrPair(
        "permiso_denegado",
        "Se requieren privilegios de Administrador. Ejecuta la aplicación como Administrador."));
  }

  NET_LUID luid{};
  GetInterfaceLuid(U8ToW(*iface_str), luid);

  std::vector<std::wstring> added_now;
  for (const auto& entry : *subnets_list) {
    const auto* dest_s = std::get_if<std::string>(&entry);
    if (!dest_s || dest_s->empty()) continue;
    if (RouteExists(U8ToW(*dest_s), U8ToW(*gw_str), U8ToW(*iface_str))) {
      // Track even if already exists to allow cleanup
      {
        std::lock_guard<std::mutex> lock(g_routes_mutex);
        TrackedRoute tr;
        tr.dest_cidr = U8ToW(*dest_s);
        tr.gateway = U8ToW(*gw_str);
        tr.iface = U8ToW(*iface_str);
        tr.luid = luid;
        bool exists_tr = false;
        for (const auto& t : g_tracked_routes) {
          if (t.dest_cidr == tr.dest_cidr && t.luid.Value == tr.luid.Value) { exists_tr = true; break; }
        }
        if (!exists_tr) g_tracked_routes.push_back(tr);
      }
      continue;
    }
    auto r = HandleAddRoute(*dest_s, *gw_str, *iface_str);
    if (auto* err = std::get_if<flutter::CustomEncodableValue>(r.get())) {
      for (const auto& added : added_now) {
        RemoveRouteNative(added);
      }
      std::string err_code, err_msg;
      DecodeErrPair(*err, &err_code, &err_msg);
      std::string msg = "Error al agregar ruta " + *dest_s +
          " (se revirtieron los cambios): " + err_msg;
      return std::make_unique<EncodableValue>(
          ErrPair("error_tunel_dividido", msg));
    }
    added_now.push_back(U8ToW(*dest_s));
  }

  {
    std::lock_guard<std::mutex> lock(g_routes_mutex);
    for (const auto& dest : added_now) {
      TrackedRoute tr;
      tr.dest_cidr = dest;
      tr.gateway = U8ToW(*gw_str);
      tr.iface = U8ToW(*iface_str);
      tr.luid = luid;
      bool exists_tr = false;
      for (const auto& t : g_tracked_routes) {
        if (t.dest_cidr == tr.dest_cidr && t.luid.Value == tr.luid.Value) { exists_tr = true; break; }
      }
      if (!exists_tr) g_tracked_routes.push_back(tr);
    }
  }

  return std::make_unique<EncodableValue>(
      std::string("Túnel dividido habilitado exitosamente. ") +
      std::to_string(added_now.size()) +
      " ruta(s) agregada(s).");
}

// ------------------------------------------------------------------
//  disableSplitTunnel
// ------------------------------------------------------------------
static std::unique_ptr<EncodableValue> HandleDisableSplitTunnel() {
  if (!IsElevated()) {
    return std::make_unique<EncodableValue>(ErrPair(
        "permiso_denegado",
        "Se requieren privilegios de Administrador"));
  }

  std::vector<TrackedRoute> routes_copy;
  {
    std::lock_guard<std::mutex> lock(g_routes_mutex);
    routes_copy = std::move(g_tracked_routes);
    g_tracked_routes.clear();
  }

  std::stringstream results;
  if (routes_copy.empty()) {
    results << "No hay rutas de túnel dividido activas.";
    return std::make_unique<EncodableValue>(results.str());
  }
  for (const auto& tr : routes_copy) {
    const DWORD status = RemoveRouteNative(tr.dest_cidr);
    if (status == NO_ERROR || status == ERROR_NOT_FOUND) {
      results << "Ruta " << WToU8(tr.dest_cidr) << " eliminada. ";
    } else {
      results << "Error al eliminar " << WToU8(tr.dest_cidr) << ": código " << status << ". ";
    }
  }
  return std::make_unique<EncodableValue>(results.str());
}

// ------------------------------------------------------------------
//  getRoutes
// ------------------------------------------------------------------
static std::unique_ptr<EncodableValue> HandleGetRoutes() {
  auto res = RunCmdSync(L"route print -4");
  std::string out = WToU8(res.output);
  if (out.empty()) {
    res = RunCmdSync(L"netsh interface ipv4 show routes");
    out = WToU8(res.output);
  }
  return std::make_unique<EncodableValue>(out);
}

// ------------------------------------------------------------------
//  getPrimaryDefaultRouteInfo
// ------------------------------------------------------------------
static std::unique_ptr<EncodableValue> HandleGetPrimaryDefaultRouteInfo() {
  EncodableMap out;
  out[EncodableValue("interfaceName")] = EncodableValue("");
  out[EncodableValue("gateway")] = EncodableValue("");
  out[EncodableValue("routeMetric")] = EncodableValue("");

  // Intentar con GetAdaptersAddresses (nativo, más fiable)
  {
    ULONG flags = GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER;
    ULONG size = 0;
    if (GetAdaptersAddresses(AF_INET, flags, NULL, NULL, &size) == ERROR_BUFFER_OVERFLOW) {
      std::vector<BYTE> buf(size);
      PIP_ADAPTER_ADDRESSES adapters = (PIP_ADAPTER_ADDRESSES)buf.data();
      if (GetAdaptersAddresses(AF_INET, flags, NULL, adapters, &size) == NO_ERROR) {
        // Buscar adaptador con gateway por defecto
        for (PIP_ADAPTER_ADDRESSES cur = adapters; cur != NULL; cur = cur->Next) {
          if (cur->OperStatus != IfOperStatusUp) continue;
          if (cur->FirstGatewayAddress == NULL) continue;
          char gw_str[INET_ADDRSTRLEN] = {0};
          struct sockaddr_in* sa = (struct sockaddr_in*)cur->FirstGatewayAddress->Address.lpSockaddr;
          if (sa && sa->sin_family == AF_INET) {
            inet_ntop(AF_INET, &sa->sin_addr, gw_str, INET_ADDRSTRLEN);
            if (gw_str[0] != '\0') {
              char name[256] = {0};
              if (cur->FriendlyName) {
                WideCharToMultiByte(CP_UTF8, 0, cur->FriendlyName, -1, name, 255, NULL, NULL);
              } else if (cur->AdapterName) {
                strncpy(name, cur->AdapterName, 255);
              }
              out[EncodableValue("interfaceName")] = EncodableValue(std::string(name));
              out[EncodableValue("gateway")] = EncodableValue(std::string(gw_str));
              out[EncodableValue("routeMetric")] = EncodableValue("0");
              return std::make_unique<EncodableValue>(out);
            }
          }
        }
      }
    }
  }

  // Intentar con PowerShell primero
  {
    const auto res = RunCmdSync(
        L"powershell -NoProfile -ExecutionPolicy Bypass -Command \"$route = Get-NetRoute "
        L"-AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' "
        L"-ErrorAction SilentlyContinue | Sort-Object -Property RouteMetric "
        L"| Select-Object -First 1 InterfaceAlias,NextHop,RouteMetric; "
        L"if ($route) { Write-Output ($route.InterfaceAlias + '|' + "
        L"$route.NextHop + '|' + [string]$route.RouteMetric) }\"");
    if (res.exit_code == 0 && !res.output.empty()) {
      const auto line = TrimAscii(WToU8(res.output));
      const auto first_sep = line.find('|');
      const auto second_sep =
          first_sep == std::string::npos ? std::string::npos : line.find('|', first_sep + 1);
      if (first_sep != std::string::npos && second_sep != std::string::npos) {
        out[EncodableValue("interfaceName")] =
            EncodableValue(line.substr(0, first_sep));
        out[EncodableValue("gateway")] =
            EncodableValue(line.substr(first_sep + 1, second_sep - first_sep - 1));
        out[EncodableValue("routeMetric")] =
            EncodableValue(line.substr(second_sep + 1));
        return std::make_unique<EncodableValue>(out);
      }
    }
  }

  // Fallback con route print
  {
    const auto res = RunCmdSync(L"route print -4 0.0.0.0");
    if (res.exit_code == 0 && !res.output.empty()) {
      const auto text = WToU8(res.output);
      std::istringstream iss(text);
      std::string line;
      while (std::getline(iss, line)) {
        if (line.find("0.0.0.0") == std::string::npos) continue;
        if (line.find("On-link") != std::string::npos) continue;
        std::vector<std::string> parts;
        std::string token;
        std::istringstream pss(line);
        while (pss >> token) {
          parts.push_back(token);
        }
        if (parts.size() >= 5) {
          out[EncodableValue("gateway")] = EncodableValue(parts[2]);
          out[EncodableValue("interfaceName")] = EncodableValue(parts[3]);
          out[EncodableValue("routeMetric")] = EncodableValue(parts[4]);
          return std::make_unique<EncodableValue>(out);
        }
      }
    }
  }

  // Fallback nativo con GetIpForwardTable2
  {
    PMIB_IPFORWARD_TABLE2 table = nullptr;
    if (GetIpForwardTable2(AF_INET, &table) == NO_ERROR) {
      ULONG best_metric = ULONG_MAX;
      MIB_IPFORWARD_ROW2* best_row = nullptr;
      for (ULONG i = 0; i < table->NumEntries; ++i) {
        auto& row = table->Table[i];
        if (row.DestinationPrefix.PrefixLength == 0) {
          if (row.Metric < best_metric && row.NextHop.Ipv4.sin_addr.S_un.S_addr != 0) {
            best_metric = row.Metric;
            best_row = &row;
          }
        }
      }
      if (best_row != nullptr) {
        char gw_str[INET_ADDRSTRLEN];
        char if_str[IF_MAX_STRING_SIZE + 1] = {0};
        inet_ntop(AF_INET, &best_row->NextHop.Ipv4.sin_addr, gw_str, INET_ADDRSTRLEN);
        if (best_row->InterfaceAlias[0] != 0) {
          WideCharToMultiByte(CP_UTF8, 0, best_row->InterfaceAlias, -1, if_str, IF_MAX_STRING_SIZE, NULL, NULL);
        } else if (best_row->InterfaceLuid.Value != 0) {
          NET_IFINDEX idx = 0;
          ConvertInterfaceLuidToIndex(&best_row->InterfaceLuid, &idx);
          IF_INDEX ifindex = (IF_INDEX)idx;
          char name[IF_NAMESIZE];
          if (if_indextoname(ifindex, name)) {
            strncpy(if_str, name, IF_MAX_STRING_SIZE);
          }
        }
        out[EncodableValue("gateway")] = EncodableValue(std::string(gw_str));
        out[EncodableValue("interfaceName")] = EncodableValue(std::string(if_str));
        out[EncodableValue("routeMetric")] = EncodableValue(std::to_string(best_metric));
        FreeMibTable(table);
        return std::make_unique<EncodableValue>(out);
      }
      FreeMibTable(table);
    }
  }

  return std::make_unique<EncodableValue>(out);
}

// ------------------------------------------------------------------
//  listInterfaces
// ------------------------------------------------------------------
static std::unique_ptr<EncodableValue> HandleListInterfaces() {
  EncodableList out_list;

  if (out_list.empty()) {
    auto res = RunCmdSync(L"netsh interface show interface");
    auto lines = WToU8(res.output);
    std::istringstream iss(lines);
    std::string line;
    while (std::getline(iss, line)) {
      if (line.find("---") != std::string::npos) continue;
      if (line.find("Admin State") != std::string::npos ||
          line.find("Nombre de interfaz") != std::string::npos ||
          line.find("Interface Name") != std::string::npos) continue;
      if (line.empty()) continue;
      auto pos = line.find_last_not_of(" \t\r\n");
      if (pos == std::string::npos) continue;
      auto end = line.find_last_of(" \t");
      if (end == std::string::npos || end >= pos) {
        out_list.push_back(line.substr(0, pos + 1));
      } else {
        std::string name = line.substr(end + 1, pos - end);
        if (!name.empty()) out_list.push_back(name);
      }
    }
  }

  return std::make_unique<EncodableValue>(out_list);
}

// ------------------------------------------------------------------
//  verifyRoutes
// ------------------------------------------------------------------
static std::unique_ptr<EncodableValue> HandleVerifyRoutes(
    const EncodableValue* args) {
  const auto* map = std::get_if<EncodableMap>(args);
  if (!map) {
    return std::make_unique<EncodableValue>(ErrPair(
        "argumento_invalido", "Se requiere un mapa de argumentos"));
  }

  const EncodableValue* subnets_val = nullptr;
  const EncodableValue* gw_val = nullptr;
  const EncodableValue* iface_val = nullptr;
  for (const auto& [k, v] : *map) {
    if (const auto* ks = std::get_if<std::string>(&k)) {
      if (*ks == "hospitalSubnets") subnets_val = &v;
      else if (*ks == "gateway") gw_val = &v;
      else if (*ks == "interfaceName") iface_val = &v;
    }
  }

  const auto* subnets_list =
      subnets_val ? std::get_if<EncodableList>(subnets_val) : nullptr;
  const auto* gw_str = gw_val ? std::get_if<std::string>(gw_val) : nullptr;
  const auto* iface_str =
      iface_val ? std::get_if<std::string>(iface_val) : nullptr;

  if (!subnets_list || !gw_str || !iface_str) {
    return std::make_unique<EncodableValue>(ErrPair(
        "argumento_invalido",
        "Se requieren hospitalSubnets (lista), gateway, interfaceName"));
  }

  EncodableList missing;
  for (const auto& entry : *subnets_list) {
    const auto* dest_s = std::get_if<std::string>(&entry);
    if (!dest_s || dest_s->empty()) continue;
    if (!RouteExists(U8ToW(*dest_s), U8ToW(*gw_str), U8ToW(*iface_str))) {
      missing.push_back(EncodableValue(*dest_s));
    }
  }
  return std::make_unique<EncodableValue>(missing);
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

  if (method == "addRoute") {
    std::string dest, gw, iface;
    if (const auto* map = std::get_if<EncodableMap>(args)) {
      for (const auto& [k, v] : *map) {
        if (const auto* ks = std::get_if<std::string>(&k)) {
          if (*ks == "destinationCidr") {
            if (auto* s = std::get_if<std::string>(&v)) dest = *s;
          } else if (*ks == "gateway") {
            if (auto* s = std::get_if<std::string>(&v)) gw = *s;
          } else if (*ks == "interfaceName") {
            if (auto* s = std::get_if<std::string>(&v)) iface = *s;
          }
        }
      }
    }
    r = HandleAddRoute(dest, gw, iface);
  } else if (method == "removeRoute") {
    std::string dest;
    if (const auto* map = std::get_if<EncodableMap>(args)) {
      for (const auto& [k, v] : *map) {
        if (const auto* ks = std::get_if<std::string>(&k)) {
          if (*ks == "destinationCidr") {
            if (auto* s = std::get_if<std::string>(&v)) dest = *s;
          }
        }
      }
    }
    r = HandleRemoveRoute(dest);
  } else if (method == "enableSplitTunnel") {
    r = HandleEnableSplitTunnel(args);
  } else if (method == "disableSplitTunnel") {
    r = HandleDisableSplitTunnel();
  } else if (method == "getRoutes") {
    r = HandleGetRoutes();
  } else if (method == "getPrimaryDefaultRouteInfo") {
    r = HandleGetPrimaryDefaultRouteInfo();
  } else if (method == "listInterfaces") {
    r = HandleListInterfaces();
  } else if (method == "verifyRoutes") {
    r = HandleVerifyRoutes(args);
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
  } else {
    result->Success(*r);
  }
}

}  // namespace

void RouteManagerPluginRegisterWithRegistrar(
    flutter::FlutterEngine* engine) {
  auto channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      engine->messenger(), "com.medlinkconnect/route_manager",
      &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(HandleMethodCall);
  static std::vector<MethodChannelPtr> s_channels;
  s_channels.push_back(std::move(channel));
}
