#include "route_manager_plugin.h"

#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <iphlpapi.h>
#include <netioapi.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <stdlib.h>
#include <any>
#include <string>
#include <climits>
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
  if (!GetInterfaceLuid(iface, luid)) return false;

  SOCKADDR_INET dest_addr{}, gw_addr{};
  UINT8 prefix;
  if (!ParseCIDR(dest_cidr, dest_addr, prefix)) return false;
  if (!ParseIPv4(gw, gw_addr)) return false;

  PMIB_IPFORWARD_TABLE2 table = nullptr;
  if (GetIpForwardTable2(AF_INET, &table) != NO_ERROR) return false;

  bool found = false;
  for (ULONG i = 0; i < table->NumEntries; ++i) {
    const auto& row = table->Table[i];
    if (row.DestinationPrefix.PrefixLength != prefix) continue;
    if (row.DestinationPrefix.Prefix.Ipv4.sin_addr.S_un.S_addr !=
        dest_addr.Ipv4.sin_addr.S_un.S_addr) {
      continue;
    }
    if (row.InterfaceLuid.Value != luid.Value) continue;
    if (row.NextHop.Ipv4.sin_family != AF_INET) continue;
    if (row.NextHop.Ipv4.sin_addr.S_un.S_addr !=
        gw_addr.Ipv4.sin_addr.S_un.S_addr) {
      continue;
    }
    found = true;
    break;
  }
  FreeMibTable(table);
  return found;
}

static bool RowMatches(const MIB_IPFORWARD_ROW2& row,
                       const SOCKADDR_INET& dest_addr,
                       UINT8 prefix,
                       const SOCKADDR_INET& gw_addr,
                       NET_LUID luid) {
  return row.DestinationPrefix.PrefixLength == prefix &&
         row.DestinationPrefix.Prefix.Ipv4.sin_addr.S_un.S_addr ==
             dest_addr.Ipv4.sin_addr.S_un.S_addr &&
         row.InterfaceLuid.Value == luid.Value &&
         row.NextHop.Ipv4.sin_family == AF_INET &&
         row.NextHop.Ipv4.sin_addr.S_un.S_addr ==
             gw_addr.Ipv4.sin_addr.S_un.S_addr;
}

static DWORD AddRouteNative(const std::wstring& dest_cidr,
                            const std::wstring& gw,
                            const std::wstring& iface_alias) {
  MIB_IPFORWARD_ROW2 row;
  InitializeIpForwardEntry(&row);

  if (!GetInterfaceLuid(iface_alias, row.InterfaceLuid))
    return ERROR_NOT_FOUND;

  UINT8 prefix;
  if (!ParseCIDR(dest_cidr, row.DestinationPrefix.Prefix, prefix))
    return ERROR_INVALID_PARAMETER;
  row.DestinationPrefix.PrefixLength = prefix;

  if (!ParseIPv4(gw, row.NextHop)) return ERROR_INVALID_PARAMETER;
  row.NextHop.Ipv4.sin_family = AF_INET;

  row.Metric = 0;
  row.SitePrefixLength = 0;

  return CreateIpForwardEntry2(&row);
}

static DWORD RemoveRouteNative(const std::wstring& dest_cidr,
                               const std::wstring& gw,
                               const std::wstring& iface_alias) {
  NET_LUID luid;
  if (!GetInterfaceLuid(iface_alias, luid)) return ERROR_NOT_FOUND;

  SOCKADDR_INET dest_addr{}, gw_addr{};
  UINT8 prefix;
  if (!ParseCIDR(dest_cidr, dest_addr, prefix))
    return ERROR_INVALID_PARAMETER;
  if (!ParseIPv4(gw, gw_addr)) return ERROR_INVALID_PARAMETER;

  PMIB_IPFORWARD_TABLE2 table = nullptr;
  if (GetIpForwardTable2(AF_INET, &table) != NO_ERROR) return ERROR_NOT_FOUND;

  bool removed = false;
  DWORD last_err = ERROR_NOT_FOUND;
  for (ULONG i = 0; i < table->NumEntries; ++i) {
    const auto& row = table->Table[i];
    if (!RowMatches(row, dest_addr, prefix, gw_addr, luid)) continue;

    MIB_IPFORWARD_ROW2 row_copy = row;
    const DWORD status = DeleteIpForwardEntry2(&row_copy);
    if (status == NO_ERROR) {
      removed = true;
    } else if (status != ERROR_NOT_FOUND) {
      last_err = status;
    }
  }
  FreeMibTable(table);
  return removed ? NO_ERROR : last_err;
}

static void TrackRoute(const std::wstring& dest_cidr,
                       const std::wstring& gw,
                       const std::wstring& iface,
                       NET_LUID luid) {
  std::lock_guard<std::mutex> lock(g_routes_mutex);
  for (const auto& tracked : g_tracked_routes) {
    if (tracked.dest_cidr == dest_cidr && tracked.gateway == gw &&
        tracked.iface == iface && tracked.luid.Value == luid.Value) {
      return;
    }
  }
  TrackedRoute route;
  route.dest_cidr = dest_cidr;
  route.gateway = gw;
  route.iface = iface;
  route.luid = luid;
  g_tracked_routes.push_back(route);
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

  NET_LUID luid{};
  if (!GetInterfaceLuid(wiface, luid)) {
    return std::make_unique<EncodableValue>(ErrPair(
        "argumento_invalido", "No se encontró la interfaz indicada."));
  }

  if (RouteExists(wdest, wgw, wiface)) {
    return std::make_unique<EncodableValue>(
        "La ruta " + dest + " ya existe para la interfaz indicada.");
  }

  const DWORD status = AddRouteNative(wdest, wgw, wiface);
  if (status == ERROR_OBJECT_ALREADY_EXISTS) {
    return std::make_unique<EncodableValue>(
        "La ruta " + dest + " ya existe para la interfaz indicada.");
  }
  if (status != NO_ERROR) {
    std::string msg = "Error al agregar ruta " + dest + ": código " +
                      std::to_string(status);
    return std::make_unique<EncodableValue>(ErrPair("error_comando", msg));
  }

  if (!RouteExists(wdest, wgw, wiface)) {
    RemoveRouteNative(wdest, wgw, wiface);
    return std::make_unique<EncodableValue>(ErrPair(
        "error_verificacion",
        "La ruta " + dest + " no pudo verificarse tras agregarla."));
  }

  TrackRoute(wdest, wgw, wiface, luid);
  return std::make_unique<EncodableValue>(
      "Ruta " + dest + " agregada exitosamente.");
}

// ------------------------------------------------------------------
//  removeRoute
// ------------------------------------------------------------------
static std::unique_ptr<EncodableValue> HandleRemoveRoute(
    const std::string& dest, const std::string& gw,
    const std::string& iface) {
  if (dest.empty()) {
    return std::make_unique<EncodableValue>(ErrPair(
        "argumento_invalido", "Falta destinationCidr"));
  }
  if (!IsElevated()) {
    return std::make_unique<EncodableValue>(ErrPair(
        "permiso_denegado",
        "Se requieren privilegios de Administrador"));
  }

  const auto wdest = U8ToW(dest);

  // Limpieza exacta de una ruta dejada por una sesión anterior.
  if (!gw.empty() && !iface.empty()) {
    const DWORD status =
        RemoveRouteNative(wdest, U8ToW(gw), U8ToW(iface));
    if (status == NO_ERROR || status == ERROR_NOT_FOUND) {
      return std::make_unique<EncodableValue>(
          "Ruta " + dest + " eliminada.");
    }
    return std::make_unique<EncodableValue>(ErrPair(
        "error_comando",
        "No se pudo eliminar la ruta " + dest + ": código " +
            std::to_string(status) + "."));
  }
  std::string failures;
  size_t removed_count = 0;

  {
    std::lock_guard<std::mutex> lock(g_routes_mutex);
    std::vector<TrackedRoute> remaining;
    for (const auto& tracked : g_tracked_routes) {
      if (tracked.dest_cidr != wdest) {
        remaining.push_back(tracked);
        continue;
      }
      const DWORD status = RemoveRouteNative(tracked.dest_cidr,
                                             tracked.gateway, tracked.iface);
      if (status == NO_ERROR || status == ERROR_NOT_FOUND) {
        removed_count++;
      } else {
        remaining.push_back(tracked);
        failures += "No se pudo eliminar " + WToU8(tracked.dest_cidr) +
                    ": código " + std::to_string(status) + ". ";
      }
    }
    g_tracked_routes.swap(remaining);
  }

  if (!failures.empty()) {
    return std::make_unique<EncodableValue>(
        ErrPair("error_comando", failures));
  }
  if (removed_count == 0) {
    return std::make_unique<EncodableValue>(
        "No hay una ruta registrada por la aplicación para " + dest + ".");
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
  if (!IsElevated()) {
    return std::make_unique<EncodableValue>(ErrPair(
        "permiso_denegado",
        "Se requieren privilegios de Administrador. Ejecuta la aplicación como Administrador."));
  }

  const auto wgw = U8ToW(*gw_str);
  const auto wiface = U8ToW(*iface_str);
  NET_LUID luid{};
  if (!GetInterfaceLuid(wiface, luid)) {
    return std::make_unique<EncodableValue>(ErrPair(
        "argumento_invalido", "No se encontró la interfaz indicada."));
  }

  std::vector<TrackedRoute> added_now;
  for (const auto& entry : *subnets_list) {
    const auto* dest_s = std::get_if<std::string>(&entry);
    if (!dest_s || dest_s->empty()) continue;

    const auto wdest = U8ToW(*dest_s);
    if (RouteExists(wdest, wgw, wiface)) {
      continue;
    }

    const DWORD status = AddRouteNative(wdest, wgw, wiface);
    if (status == ERROR_OBJECT_ALREADY_EXISTS) {
      continue;
    }
    if (status != NO_ERROR || !RouteExists(wdest, wgw, wiface)) {
      for (const auto& added : added_now) {
        RemoveRouteNative(added.dest_cidr, added.gateway, added.iface);
      }
      std::string msg = "Error al agregar ruta " + *dest_s +
          " (se revirtieron los cambios): código " +
          std::to_string(status);
      return std::make_unique<EncodableValue>(
          ErrPair("error_tunel_dividido", msg));
    }

    TrackedRoute route;
    route.dest_cidr = wdest;
    route.gateway = wgw;
    route.iface = wiface;
    route.luid = luid;
    added_now.push_back(route);
  }

  {
    std::lock_guard<std::mutex> lock(g_routes_mutex);
    for (const auto& route : added_now) {
      bool tracked = false;
      for (const auto& existing : g_tracked_routes) {
        if (existing.dest_cidr == route.dest_cidr &&
            existing.gateway == route.gateway &&
            existing.iface == route.iface &&
            existing.luid.Value == route.luid.Value) {
          tracked = true;
          break;
        }
      }
      if (!tracked) g_tracked_routes.push_back(route);
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
    routes_copy.swap(g_tracked_routes);
  }

  if (routes_copy.empty()) {
    return std::make_unique<EncodableValue>(
        "No hay rutas de túnel dividido activas.");
  }

  std::stringstream results;
  std::vector<TrackedRoute> remaining;
  for (const auto& tracked : routes_copy) {
    const DWORD status = RemoveRouteNative(tracked.dest_cidr,
                                           tracked.gateway, tracked.iface);
    if (status == NO_ERROR || status == ERROR_NOT_FOUND) {
      results << "Ruta " << WToU8(tracked.dest_cidr) << " eliminada. ";
    } else {
      remaining.push_back(tracked);
      results << "Error al eliminar " << WToU8(tracked.dest_cidr)
              << ": código " << status << ". ";
    }
  }

  if (!remaining.empty()) {
    std::lock_guard<std::mutex> lock(g_routes_mutex);
    g_tracked_routes.insert(g_tracked_routes.end(), remaining.begin(),
                            remaining.end());
    return std::make_unique<EncodableValue>(
        ErrPair("error_comando", results.str()));
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

  PMIB_IPFORWARD_TABLE2 table = nullptr;
  if (GetIpForwardTable2(AF_INET, &table) != NO_ERROR) {
    return std::make_unique<EncodableValue>(out);
  }

  ULONG best_metric = ULONG_MAX;
  MIB_IPFORWARD_ROW2 best_row{};
  bool found = false;
  for (ULONG i = 0; i < table->NumEntries; ++i) {
    const auto& row = table->Table[i];
    if (row.DestinationPrefix.PrefixLength != 0) continue;
    if (row.NextHop.Ipv4.sin_family != AF_INET) continue;
    if (row.NextHop.Ipv4.sin_addr.S_un.S_addr == 0) continue;

    ULONG interface_metric = 0;
    MIB_IPINTERFACE_ROW interface_row;
    InitializeIpInterfaceEntry(&interface_row);
    interface_row.InterfaceLuid = row.InterfaceLuid;
    interface_row.Family = AF_INET;
    if (GetIpInterfaceEntry(&interface_row) == NO_ERROR) {
      interface_metric = interface_row.Metric;
    }
    const ULONG combined = row.Metric + interface_metric;
    if (!found || combined < best_metric) {
      found = true;
      best_metric = combined;
      best_row = row;
    }
  }
  FreeMibTable(table);

  if (!found) {
    return std::make_unique<EncodableValue>(out);
  }

  char gw_str[INET_ADDRSTRLEN] = {0};
  inet_ntop(AF_INET, &best_row.NextHop.Ipv4.sin_addr, gw_str,
            INET_ADDRSTRLEN);

  std::wstring alias;
  wchar_t buffer[IF_MAX_STRING_SIZE + 1] = {0};
  if (ConvertInterfaceLuidToAlias(&best_row.InterfaceLuid, buffer,
                                  IF_MAX_STRING_SIZE + 1) == NO_ERROR) {
    alias = buffer;
  }

  out[EncodableValue("interfaceName")] = EncodableValue(WToU8(alias));
  out[EncodableValue("gateway")] = EncodableValue(std::string(gw_str));
  out[EncodableValue("routeMetric")] =
      EncodableValue(std::to_string(best_row.Metric));
  return std::make_unique<EncodableValue>(out);
}

// ------------------------------------------------------------------
//  listInterfaces
// ------------------------------------------------------------------
static std::unique_ptr<EncodableValue> HandleListInterfaces() {
  EncodableList out_list;

  PMIB_IPINTERFACE_TABLE table = nullptr;
  if (GetIpInterfaceTable(AF_INET, &table) != NO_ERROR) {
    return std::make_unique<EncodableValue>(out_list);
  }

  std::vector<std::string> seen;
  for (ULONG i = 0; i < table->NumEntries; ++i) {
    wchar_t buffer[IF_MAX_STRING_SIZE + 1] = {0};
    if (ConvertInterfaceLuidToAlias(&table->Table[i].InterfaceLuid, buffer,
                                    IF_MAX_STRING_SIZE + 1) != NO_ERROR) {
      continue;
    }
    const std::string alias = WToU8(buffer);
    if (alias.empty()) continue;
    bool duplicate = false;
    for (const auto& existing : seen) {
      if (existing == alias) {
        duplicate = true;
        break;
      }
    }
    if (duplicate) continue;
    seen.push_back(alias);
    out_list.push_back(EncodableValue(alias));
  }
  FreeMibTable(table);

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
    std::string gw;
    std::string iface;
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
    r = HandleRemoveRoute(dest, gw, iface);
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
