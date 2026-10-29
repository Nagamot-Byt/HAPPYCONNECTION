#include "route_manager_plugin.h"

#include <glib.h>

#include <algorithm>
#include <limits>
#include <string>
#include <vector>

#include "async_method_call.h"
#include "process_utils.h"

namespace {

struct TrackedRoute {
  std::string destination;
  std::string gateway;
  std::string interface_name;
};

GList* g_tracked_routes = nullptr;
GMutex g_routes_mutex;

class MutexLock {
 public:
  explicit MutexLock(GMutex* mutex) : mutex_(mutex) { g_mutex_lock(mutex_); }
  ~MutexLock() { g_mutex_unlock(mutex_); }
  MutexLock(const MutexLock&) = delete;
  MutexLock& operator=(const MutexLock&) = delete;

 private:
  GMutex* mutex_;
};

void free_tracked_route(gpointer data) {
  delete static_cast<TrackedRoute*>(data);
}

std::vector<std::string> split_route_line(const gchar* line) {
  std::vector<std::string> tokens;
  gchar** parts = g_strsplit_set(line, " \t", -1);
  for (gchar** part = parts; part && *part; ++part) {
    if (**part) tokens.emplace_back(*part);
  }
  g_strfreev(parts);
  return tokens;
}

bool route_line_matches(const gchar* line,
                        const std::string& destination,
                        const std::string& gateway,
                        const std::string& interface_name) {
  const auto tokens = split_route_line(line);
  if (tokens.empty() || tokens.front() != destination) return false;

  bool has_gateway = false;
  bool has_interface = false;
  for (size_t i = 0; i + 1 < tokens.size(); ++i) {
    if (tokens[i] == "via" && tokens[i + 1] == gateway) {
      has_gateway = true;
    } else if (tokens[i] == "dev" && tokens[i + 1] == interface_name) {
      has_interface = true;
    }
  }
  return has_gateway && has_interface;
}

bool route_exists(const std::string& destination,
                  const std::string& gateway,
                  const std::string& interface_name) {
  gchar* out = nullptr;
  gchar* err = nullptr;
  gint exit_code = 0;
  const gboolean ran = run_program({"ip", "route", "show", destination}, &out,
                                   &err, &exit_code);
  const bool found = ran && exit_code == 0 && out &&
                     route_line_matches(out, destination, gateway,
                                        interface_name);
  g_free(out);
  g_free(err);
  return found;
}

bool delete_route_exact(const std::string& destination,
                        const std::string& gateway,
                        const std::string& interface_name) {
  gchar* out = nullptr;
  gchar* err = nullptr;
  gint exit_code = 0;
  const gboolean ran = run_privileged(
      {"ip", "route", "del", destination, "via", gateway, "dev",
       interface_name},
      &out, &err, &exit_code);
  g_free(out);
  g_free(err);
  return ran && exit_code == 0;
}

void track_route_locked(const TrackedRoute& route) {
  for (GList* item = g_tracked_routes; item; item = item->next) {
    const auto* tracked = static_cast<const TrackedRoute*>(item->data);
    if (tracked->destination == route.destination &&
        tracked->gateway == route.gateway &&
        tracked->interface_name == route.interface_name) {
      return;
    }
  }
  g_tracked_routes =
      g_list_prepend(g_tracked_routes, new TrackedRoute(route));
}

bool has_invalid_chars(const gchar* value) {
  if (!value) return true;
  for (const guchar* p = reinterpret_cast<const guchar*>(value); *p; ++p) {
    if (*p < 0x20 || *p == 0x7f || *p == '\'') return true;
  }
  return false;
}

FlMethodResponse* error_response(const gchar* code, const std::string& message) {
  return FL_METHOD_RESPONSE(
      fl_method_error_response_new(code, message.c_str(), nullptr));
}

FlMethodResponse* success_string(const std::string& message) {
  return FL_METHOD_RESPONSE(
      fl_method_success_response_new(fl_value_new_string(message.c_str())));
}

FlMethodResponse* handle_add_route(const gchar* dest,
                                   const gchar* gw,
                                   const gchar* iface) {
  if (!dest || !*dest || !gw || !*gw || !iface || !*iface) {
    return error_response(
        "argumento_invalido",
        "Faltan parámetros: destinationCidr, gateway, interfaceName");
  }
  if (has_invalid_chars(dest) || has_invalid_chars(gw) ||
      has_invalid_chars(iface)) {
    return error_response("argumento_invalido",
                          "Los parámetros contienen caracteres inválidos.");
  }

  if (route_exists(dest, gw, iface)) {
    return success_string("La ruta ya existe para la interfaz indicada.");
  }

  gchar* out = nullptr;
  gchar* err = nullptr;
  gint exit_code = 0;
  const gboolean ran = run_privileged(
      {"ip", "route", "add", dest, "via", gw, "dev", iface}, &out, &err,
      &exit_code);
  g_free(out);
  if (!ran || exit_code != 0) {
    const std::string detail = err && *err ? err : "desconocido";
    g_free(err);
    return error_response("error_comando",
                          std::string("Error al agregar ruta ") + dest + ": " +
                              detail);
  }
  g_free(err);

  if (!route_exists(dest, gw, iface)) {
    delete_route_exact(dest, gw, iface);
    return error_response(
        "error_verificacion",
        std::string("La ruta ") + dest + " no pudo verificarse tras agregarla.");
  }

  {
    MutexLock lock(&g_routes_mutex);
    track_route_locked(TrackedRoute{dest, gw, iface});
  }
  return success_string(std::string("Ruta ") + dest + " agregada exitosamente.");
}

FlMethodResponse* handle_remove_route(const gchar* dest, const gchar* gw,
                                     const gchar* iface) {
  if (!dest || !*dest) {
    return error_response("argumento_invalido", "Falta destinationCidr");
  }
  if (has_invalid_chars(dest)) {
    return error_response("argumento_invalido",
                          "destinationCidr contiene caracteres inválidos.");
  }

  // Limpieza exacta de una ruta dejada por una sesión anterior.
  if (gw && *gw && iface && *iface) {
    if (has_invalid_chars(gw) || has_invalid_chars(iface)) {
      return error_response("argumento_invalido",
                            "gateway o interfaz contienen caracteres inválidos.");
    }
    if (!route_exists(dest, gw, iface)) {
      return success_string(std::string("La ruta ") + dest +
                            " ya no existe; nada que limpiar.");
    }
    if (delete_route_exact(dest, gw, iface) || !route_exists(dest, gw, iface)) {
      return success_string(std::string("Ruta ") + dest + " eliminada.");
    }
    return error_response("error_comando",
                          std::string("No se pudo eliminar la ruta ") + dest +
                              ".");
  }

  MutexLock lock(&g_routes_mutex);
  GList* remaining = nullptr;
  GList* removed = nullptr;
  std::string failures;

  for (GList* item = g_tracked_routes; item; item = item->next) {
    auto* route = static_cast<TrackedRoute*>(item->data);
    if (route->destination == dest) {
      if (delete_route_exact(route->destination, route->gateway,
                             route->interface_name)) {
        removed = g_list_prepend(removed, route);
      } else if (!route_exists(route->destination, route->gateway,
                               route->interface_name)) {
        removed = g_list_prepend(removed, route);
      } else {
        remaining = g_list_prepend(remaining, route);
        failures += "No se pudo eliminar " + route->destination + ". ";
      }
    } else {
      remaining = g_list_prepend(remaining, route);
    }
  }

  g_list_free(g_tracked_routes);
  g_tracked_routes = remaining;
  g_list_free_full(removed, free_tracked_route);

  if (!failures.empty()) {
    return error_response("error_comando", failures);
  }
  return success_string(std::string("Ruta ") + dest +
                        " eliminada (solo si fue agregada por la aplicación).");
}

FlMethodResponse* handle_enable_split_tunnel(
    const std::vector<std::string>& subnets,
    const std::string& gateway,
    const std::string& interface_name) {
  if (gateway.empty() || interface_name.empty() ||
      has_invalid_chars(gateway.c_str()) ||
      has_invalid_chars(interface_name.c_str())) {
    return error_response("argumento_invalido",
                          "Gateway o interfaz inválidos.");
  }

  std::vector<TrackedRoute> added_now;

  for (const auto& dest : subnets) {
    if (dest.empty() || has_invalid_chars(dest.c_str())) {
      return error_response("argumento_invalido", "Subred inválida.");
    }

    if (route_exists(dest, gateway, interface_name)) {
      continue;
    }

    gchar* out = nullptr;
    gchar* err = nullptr;
    gint exit_code = 0;
    const gboolean ran = run_privileged(
        {"ip", "route", "add", dest, "via", gateway, "dev", interface_name},
        &out, &err, &exit_code);
    g_free(out);
    if (!ran || exit_code != 0 || !route_exists(dest, gateway, interface_name)) {
      const std::string detail = err && *err ? err : "desconocido";
      g_free(err);

      for (const auto& previous : added_now) {
        delete_route_exact(previous.destination, previous.gateway,
                           previous.interface_name);
      }
      return error_response(
          "error_tunel_dividido",
          std::string("Error al agregar ruta ") + dest +
              " (se revirtieron los cambios): " + detail);
    }
    g_free(err);
    added_now.push_back(TrackedRoute{dest, gateway, interface_name});
  }

  {
    MutexLock lock(&g_routes_mutex);
    for (const auto& route : added_now) {
      track_route_locked(route);
    }
  }

  return success_string(
      "Túnel dividido habilitado exitosamente. " +
      std::to_string(added_now.size()) + " ruta(s) agregada(s).");
}

FlMethodResponse* handle_disable_split_tunnel() {
  GList* routes = nullptr;
  {
    MutexLock lock(&g_routes_mutex);
    routes = g_tracked_routes;
    g_tracked_routes = nullptr;
  }

  if (!routes) {
    return success_string("No hay rutas de túnel dividido activas.");
  }

  std::string results;
  std::string failures;
  GList* remaining = nullptr;

  for (GList* item = routes; item; item = item->next) {
    auto* route = static_cast<TrackedRoute*>(item->data);
    const bool removed =
        delete_route_exact(route->destination, route->gateway,
                           route->interface_name) ||
        !route_exists(route->destination, route->gateway,
                      route->interface_name);
    if (removed) {
      results += "Ruta " + route->destination + " eliminada. ";
      free_tracked_route(route);
    } else {
      results += "Error al eliminar " + route->destination + ". ";
      failures += "No se pudo eliminar " + route->destination + ". ";
      remaining = g_list_prepend(remaining, route);
    }
  }
  g_list_free(routes);

  if (remaining) {
    MutexLock lock(&g_routes_mutex);
    g_tracked_routes = g_list_concat(g_tracked_routes, remaining);
  }

  if (!failures.empty()) {
    return error_response("error_comando", failures + results);
  }
  return success_string(results);
}

FlMethodResponse* handle_get_routes() {
  gchar* out = nullptr;
  gchar* err = nullptr;
  gint exit_code = 0;
  const gboolean ran = run_program({"ip", "route", "show"}, &out, &err,
                                   &exit_code);
  if (!ran || exit_code != 0) {
    const std::string detail = err && *err ? err : "desconocido";
    g_free(out);
    g_free(err);
    return error_response("error_comando",
                          "No se pudieron obtener las rutas: " + detail);
  }
  FlMethodResponse* response = success_string(out ? out : "");
  g_free(out);
  g_free(err);
  return response;
}

FlMethodResponse* handle_get_primary_default_route_info() {
  gchar* out = nullptr;
  gchar* err = nullptr;
  gint exit_code = 0;
  const gboolean ran = run_program({"ip", "route", "show", "default"}, &out,
                                   &err, &exit_code);
  if (!ran || exit_code != 0) {
    const std::string detail = err && *err ? err : "desconocido";
    g_free(out);
    g_free(err);
    return error_response("error_comando",
                          "No se pudo consultar la ruta por defecto: " +
                              detail);
  }

  std::string best_gateway;
  std::string best_interface;
  std::string best_metric;
  guint64 best_metric_value = std::numeric_limits<guint64>::max();

  if (out) {
    gchar** lines = g_strsplit(out, "\n", -1);
    for (gchar** line = lines; line && *line; ++line) {
      if (!**line) continue;
      const auto tokens = split_route_line(*line);
      std::string gateway;
      std::string interface_name;
      std::string metric;
      guint64 metric_value = 0;
      for (size_t i = 0; i + 1 < tokens.size(); ++i) {
        if (tokens[i] == "via") {
          gateway = tokens[i + 1];
        } else if (tokens[i] == "dev") {
          interface_name = tokens[i + 1];
        } else if (tokens[i] == "metric") {
          metric = tokens[i + 1];
          metric_value = g_ascii_strtoull(metric.c_str(), nullptr, 10);
        }
      }
      if (gateway.empty() || interface_name.empty()) continue;
      if (metric_value < best_metric_value) {
        best_metric_value = metric_value;
        best_gateway = gateway;
        best_interface = interface_name;
        best_metric = metric;
      }
    }
    g_strfreev(lines);
  }
  g_free(out);
  g_free(err);

  g_autoptr(FlValue) map = fl_value_new_map();
  fl_value_set_string_take(map, "interfaceName",
                           fl_value_new_string(best_interface.c_str()));
  fl_value_set_string_take(map, "gateway",
                           fl_value_new_string(best_gateway.c_str()));
  fl_value_set_string_take(map, "routeMetric",
                           fl_value_new_string(best_metric.c_str()));
  return FL_METHOD_RESPONSE(
      fl_method_success_response_new(fl_value_ref(map)));
}

FlMethodResponse* handle_list_interfaces() {
  gchar* out = nullptr;
  gchar* err = nullptr;
  gint exit_code = 0;
  const gboolean ran = run_program({"ip", "-br", "link", "show"}, &out, &err,
                                   &exit_code);
  if (!ran || exit_code != 0) {
    const std::string detail = err && *err ? err : "desconocido";
    g_free(out);
    g_free(err);
    return error_response("error_comando",
                          "No se pudieron listar las interfaces: " + detail);
  }

  g_autoptr(FlValue) list = fl_value_new_list();
  if (out) {
    gchar** lines = g_strsplit(out, "\n", -1);
    for (gchar** line = lines; line && *line; ++line) {
      const auto tokens = split_route_line(*line);
      if (!tokens.empty()) {
        fl_value_append_take(list, fl_value_new_string(tokens.front().c_str()));
      }
    }
    g_strfreev(lines);
  }
  g_free(out);
  g_free(err);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_ref(list)));
}

FlMethodResponse* handle_verify_routes(
    const std::vector<std::string>& subnets,
    const std::string& gateway,
    const std::string& interface_name) {
  gchar* out = nullptr;
  gchar* err = nullptr;
  gint exit_code = 0;
  const gboolean ran =
      run_program({"ip", "route", "show"}, &out, &err, &exit_code);
  if (!ran || exit_code != 0) {
    const std::string detail = err && *err ? err : "desconocido";
    g_free(out);
    g_free(err);
    return error_response("error_comando",
                          "No se pudieron verificar las rutas: " + detail);
  }

  g_autoptr(FlValue) missing = fl_value_new_list();
  gchar** lines = out ? g_strsplit(out, "\n", -1) : nullptr;
  for (const auto& subnet : subnets) {
    if (subnet.empty()) continue;

    bool present = false;
    for (gchar** line = lines; line && *line; ++line) {
      if (route_line_matches(*line, subnet, gateway, interface_name)) {
        present = true;
        break;
      }
    }
    if (!present) {
      fl_value_append_take(missing, fl_value_new_string(subnet.c_str()));
    }
  }
  if (lines) g_strfreev(lines);
  g_free(out);
  g_free(err);

  return FL_METHOD_RESPONSE(
      fl_method_success_response_new(fl_value_ref(missing)));
}

void method_call_handler(FlMethodChannel* channel,
                         FlMethodCall* method_call,
                         gpointer user_data) {
  (void)channel;
  (void)user_data;

  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);
  const bool args_are_map =
      args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP;

  auto string_arg = [&](const gchar* key) -> std::string {
    if (!args_are_map) return {};
    FlValue* value = fl_value_lookup_string(args, key);
    if (value && fl_value_get_type(value) == FL_VALUE_TYPE_STRING) {
      return fl_value_get_string(value);
    }
    return {};
  };

  auto string_list_arg = [&](const gchar* key) -> std::vector<std::string> {
    std::vector<std::string> values;
    if (!args_are_map) return values;
    FlValue* value = fl_value_lookup_string(args, key);
    if (!value || fl_value_get_type(value) != FL_VALUE_TYPE_LIST) {
      return values;
    }
    const gsize length = fl_value_get_length(value);
    for (gsize i = 0; i < length; ++i) {
      FlValue* entry = fl_value_get_list_value(value, i);
      if (entry && fl_value_get_type(entry) == FL_VALUE_TYPE_STRING) {
        values.emplace_back(fl_value_get_string(entry));
      }
    }
    return values;
  };

  if (g_strcmp0(method, "addRoute") == 0) {
    auto dest = string_arg("destinationCidr");
    auto gw = string_arg("gateway");
    auto iface = string_arg("interfaceName");
    respond_async(method_call, [dest, gw, iface] {
      return handle_add_route(dest.empty() ? nullptr : dest.c_str(),
                              gw.empty() ? nullptr : gw.c_str(),
                              iface.empty() ? nullptr : iface.c_str());
    });
    return;
  }

  if (g_strcmp0(method, "removeRoute") == 0) {
    auto dest = string_arg("destinationCidr");
    auto gw = string_arg("gateway");
    auto iface = string_arg("interfaceName");
    respond_async(method_call, [dest, gw, iface] {
      return handle_remove_route(dest.empty() ? nullptr : dest.c_str(),
                                 gw.empty() ? nullptr : gw.c_str(),
                                 iface.empty() ? nullptr : iface.c_str());
    });
    return;
  }

  if (g_strcmp0(method, "enableSplitTunnel") == 0) {
    auto subnets = string_list_arg("hospitalSubnets");
    auto gateway = string_arg("gateway");
    auto iface = string_arg("interfaceName");
    respond_async(method_call, [subnets, gateway, iface] {
      if (gateway.empty() || iface.empty()) {
        return error_response(
            "argumento_invalido",
            "Se requieren hospitalSubnets (lista), gateway, interfaceName");
      }
      return handle_enable_split_tunnel(subnets, gateway, iface);
    });
    return;
  }

  if (g_strcmp0(method, "disableSplitTunnel") == 0) {
    respond_async(method_call, [] { return handle_disable_split_tunnel(); });
    return;
  }

  if (g_strcmp0(method, "getRoutes") == 0) {
    respond_async(method_call, [] { return handle_get_routes(); });
    return;
  }

  if (g_strcmp0(method, "getPrimaryDefaultRouteInfo") == 0) {
    respond_async(
        method_call, [] { return handle_get_primary_default_route_info(); });
    return;
  }

  if (g_strcmp0(method, "listInterfaces") == 0) {
    respond_async(method_call, [] { return handle_list_interfaces(); });
    return;
  }

  if (g_strcmp0(method, "verifyRoutes") == 0) {
    auto subnets = string_list_arg("hospitalSubnets");
    auto gateway = string_arg("gateway");
    auto iface = string_arg("interfaceName");
    respond_async(method_call, [subnets, gateway, iface] {
      if (gateway.empty() || iface.empty()) {
        return error_response(
            "argumento_invalido",
            "Se requieren hospitalSubnets, gateway, interfaceName.");
      }
      return handle_verify_routes(subnets, gateway, iface);
    });
    return;
  }

  fl_method_call_respond(
      method_call,
      FL_METHOD_RESPONSE(fl_method_not_implemented_response_new()),
      nullptr);
}

}  // namespace

void route_manager_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  static gsize mutex_initialized = 0;
  if (g_once_init_enter(&mutex_initialized)) {
    g_mutex_init(&g_routes_mutex);
    g_once_init_leave(&mutex_initialized, 1);
  }

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "com.medlinkconnect/route_manager", FL_METHOD_CODEC(codec));

  fl_method_channel_set_method_call_handler(channel, method_call_handler,
                                            nullptr, nullptr);
}
