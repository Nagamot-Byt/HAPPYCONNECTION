#include "route_manager_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar.h>
#include <flutter/standard_method_codec.h>

#include <glib.h>
#include <gio/gio.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* ------------------------------------------------------------------ */
/*  Shared state: list of subnets added by enableSplitTunnel            */
/* ------------------------------------------------------------------ */
static GList* g_tracked_routes = NULL;  /* owned strings */
static GMutex g_routes_mutex;

/* ------------------------------------------------------------------ */
/*  Helper: run a command synchronously                                 */
/* ------------------------------------------------------------------ */
static gboolean run_cmd(const gchar* cmd,
                        gchar**   stdout_out,
                        gchar**   stderr_out,
                        gint*     exit_code) {
  g_autoptr(GError) error = NULL;
  gboolean ok = g_spawn_command_line_sync(
      cmd, stdout_out, stderr_out, exit_code, &error);
  if (!ok) {
    if (stdout_out) *stdout_out = NULL;
    if (stderr_out) *stderr_out = g_strdup(error->message);
    if (exit_code)  *exit_code = -1;
  }
  return ok;
}

static gboolean is_root() { return geteuid() == 0; }

/* ------------------------------------------------------------------ */
/*  Route error helper (Spanish messages for end users)                 */
/* ------------------------------------------------------------------ */
static FlMethodResponse* permiso_denegado() {
  return FL_METHOD_RESPONSE(fl_method_error_response_new(
      "permiso_denegado",
      "Se requieren privilegios de administrador",
      nullptr));
}

/* ------------------------------------------------------------------ */
/*  addRoute                                                            */
/* ------------------------------------------------------------------ */
static FlMethodResponse* handle_add_route(const gchar* dest,
                                           const gchar* gw,
                                           const gchar* iface) {
  if (!dest || !gw || !iface) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "argumento_invalido",
        "Faltan parámetros: destinationCidr, gateway, interfaceName",
        nullptr));
  }

  if (!is_root()) return permiso_denegado();

  g_autofree gchar* add_cmd = g_strdup_printf(
      "sudo ip route add %s via %s dev %s 2>&1", dest, gw, iface);
  g_autofree gchar* out = NULL;
  g_autofree gchar* err = NULL;
  gint exit_code = 0;

  if (!run_cmd(add_cmd, &out, &err, &exit_code) || exit_code != 0) {
    g_autofree gchar* msg = g_strdup_printf(
        "Error al agregar ruta %s: %s", dest, err ? err : "desconocido");
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "error_comando", msg, nullptr));
  }

  // Verify the route was added
  g_autofree gchar* verify_cmd = g_strdup_printf(
      "ip route show %s 2>&1", dest);
  g_free(out); out = NULL;
  g_free(err); err = NULL;
  if (!run_cmd(verify_cmd, &out, &err, &exit_code) || exit_code != 0 || !out || !*out) {
    g_autofree gchar* msg = g_strdup_printf(
        "Ruta %s no verificada después de agregar", dest);
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "error_verificacion", msg, nullptr));
  }

  g_autofree gchar* msg = g_strdup_printf("Ruta %s agregada exitosamente.", dest);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(
      fl_value_new_string(msg)));
}

/* ------------------------------------------------------------------ */
/*  removeRoute                                                         */
/* ------------------------------------------------------------------ */
static FlMethodResponse* handle_remove_route(const gchar* dest) {
  if (!dest) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "argumento_invalido", "Falta destinationCidr", nullptr));
  }

  if (!is_root()) return permiso_denegado();

  g_autofree gchar* cmd = g_strdup_printf(
      "sudo ip route del %s 2>&1", dest);
  g_autofree gchar* out = NULL;
  g_autofree gchar* err = NULL;
  gint exit_code = 0;

  if (!run_cmd(cmd, &out, &err, &exit_code) || exit_code != 0) {
    g_autofree gchar* msg = g_strdup_printf(
        "Error al eliminar ruta %s: %s", dest, err ? err : "desconocido");
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "error_comando", msg, nullptr));
  }

  g_autofree gchar* msg = g_strdup_printf("Ruta %s eliminada.", dest);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(
      fl_value_new_string(msg)));
}

/* ------------------------------------------------------------------ */
/*  enableSplitTunnel (with rollback)                                   */
/* ------------------------------------------------------------------ */
static FlMethodResponse* handle_enable_split_tunnel(FlValue* args) {
  if (!args || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "argumento_invalido", "Se requiere un mapa de argumentos", nullptr));
  }

  FlValue* subnets_val = fl_value_lookup_string(args, "hospitalSubnets");
  FlValue* gw_val     = fl_value_lookup_string(args, "gateway");
  FlValue* iface_val  = fl_value_lookup_string(args, "interfaceName");

  if (!subnets_val || fl_value_get_type(subnets_val) != FL_VALUE_TYPE_LIST ||
      !gw_val     || fl_value_get_type(gw_val)     != FL_VALUE_TYPE_STRING ||
      !iface_val  || fl_value_get_type(iface_val)  != FL_VALUE_TYPE_STRING) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "argumento_invalido",
        "Se requieren hospitalSubnets (lista), gateway, interfaceName",
        nullptr));
  }

  if (!is_root()) return permiso_denegado();

  const gchar* gw    = fl_value_get_string(gw_val);
  const gchar* iface = fl_value_get_string(iface_val);

  // Track routes added in THIS call so we can rollback
  GList* added_now = NULL;
  gsize len = fl_value_get_length(subnets_val);

  for (gsize i = 0; i < len; i++) {
    FlValue* entry = fl_value_get_list_value(subnets_val, i);
    if (!entry || fl_value_get_type(entry) != FL_VALUE_TYPE_STRING) continue;
    const gchar* dest = fl_value_get_string(entry);

    g_autofree gchar* cmd = g_strdup_printf(
        "sudo ip route add %s via %s dev %s 2>&1", dest, gw, iface);
    g_autofree gchar* out = NULL;
    g_autofree gchar* err = NULL;
    gint exit_code = 0;

    if (!run_cmd(cmd, &out, &err, &exit_code) || exit_code != 0) {
      // Rollback: remove routes added in this batch
      for (GList* l = added_now; l; l = l->next) {
        g_autofree gchar* del_cmd = g_strdup_printf(
            "sudo ip route del %s 2>&1", (const gchar*)l->data);
        g_autofree gchar* d_out = NULL;
        g_autofree gchar* d_err = NULL;
        gint d_ec = 0;
        run_cmd(del_cmd, &d_out, &d_err, &d_ec);
      }
      g_list_free_full(added_now, g_free);

      g_autofree gchar* msg = g_strdup_printf(
          "Error al agregar ruta %s (se revirtieron los cambios): %s",
          dest, err ? err : "desconocido");
      return FL_METHOD_RESPONSE(fl_method_error_response_new(
          "error_tunel_dividido", msg, nullptr));
    }

    added_now = g_list_prepend(added_now, g_strdup(dest));
  }

  // Commit: add to global tracked list
  g_mutex_lock(&g_routes_mutex);
  for (GList* l = added_now; l; l = l->next) {
    // Dedup
    gboolean exists = FALSE;
    for (GList* t = g_tracked_routes; t; t = t->next) {
      if (g_strcmp0((const gchar*)t->data, (const gchar*)l->data) == 0) {
        exists = TRUE;
        break;
      }
    }
    if (!exists) {
      g_tracked_routes = g_list_prepend(g_tracked_routes,
                                         g_strdup((const gchar*)l->data));
    }
  }
  g_mutex_unlock(&g_routes_mutex);

  g_list_free_full(added_now, g_free);

  return FL_METHOD_RESPONSE(fl_method_success_response_new(
      fl_value_new_string("Túnel dividido habilitado exitosamente.")));
}

/* ------------------------------------------------------------------ */
/*  disableSplitTunnel                                                  */
/* ------------------------------------------------------------------ */
static FlMethodResponse* handle_disable_split_tunnel() {
  if (!is_root()) return permiso_denegado();

  g_mutex_lock(&g_routes_mutex);
  GList* routes = g_tracked_routes;
  g_tracked_routes = NULL;
  g_mutex_unlock(&g_routes_mutex);

  GString* results = g_string_new("");

  for (GList* l = routes; l; l = l->next) {
    const gchar* dest = (const gchar*)l->data;
    g_autofree gchar* cmd = g_strdup_printf(
        "sudo ip route del %s 2>&1", dest);
    g_autofree gchar* out = NULL;
    g_autofree gchar* err = NULL;
    gint exit_code = 0;

    if (run_cmd(cmd, &out, &err, &exit_code) && exit_code == 0) {
      g_string_append_printf(results, "Ruta %s eliminada. ", dest);
    } else {
      g_string_append_printf(results,
          "Error al eliminar %s: %s. ", dest, err ? err : "desconocido");
    }
  }

  g_list_free_full(routes, g_free);

  if (results->len == 0) {
    g_string_assign(results, "No hay rutas de túnel dividido activas.");
  }

  FlMethodResponse* resp = FL_METHOD_RESPONSE(
      fl_method_success_response_new(fl_value_new_string(results->str)));
  g_string_free(results, TRUE);
  return resp;
}

/* ------------------------------------------------------------------ */
/*  getRoutes                                                           */
/* ------------------------------------------------------------------ */
static FlMethodResponse* handle_get_routes() {
  g_autofree gchar* out = NULL;
  g_autofree gchar* err = NULL;
  gint exit_code = 0;

  if (!run_cmd("ip route show 2>&1", &out, &err, &exit_code)) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "error_comando",
        err ? err : "No se pudo obtener las rutas",
        nullptr));
  }

  return FL_METHOD_RESPONSE(fl_method_success_response_new(
      fl_value_new_string(out ? out : "")));
}

/* ------------------------------------------------------------------ */
/*  listInterfaces                                                      */
/* ------------------------------------------------------------------ */
static FlMethodResponse* handle_list_interfaces() {
  g_autofree gchar* out = NULL;
  g_autofree gchar* err = NULL;
  gint exit_code = 0;

  if (!run_cmd("ip -br link show 2>&1", &out, &err, &exit_code)) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "error_comando",
        err ? err : "No se pudieron listar las interfaces",
        nullptr));
  }

  g_autoptr(FlValue) list = fl_value_new_list();
  if (out) {
    gchar** lines = g_strsplit(out, "\n", -1);
    for (gchar** line = lines; *line; line++) {
      if (!**line) continue;
      // Format: "lo       UNKNOWN  00:00:00:00:00:00 <LOOPBACK,UP,LOWER_UP>"
      // Interface name is the first whitespace-delimited token
      g_autofree gchar* trimmed = g_strstrip(g_strdup(*line));
      gchar** tokens = g_strsplit(trimmed, " ", 2);
      if (tokens[0] && *tokens[0]) {
        fl_value_append(list, fl_value_new_string(tokens[0]));
      }
      g_strfreev(tokens);
    }
    g_strfreev(lines);
  }

  return FL_METHOD_RESPONSE(fl_method_success_response_new(
      fl_value_ref(list)));
}

/* ------------------------------------------------------------------ */
/*  Method call dispatcher                                              */
/* ------------------------------------------------------------------ */
static void method_call_handler(
    FlMethodChannel* channel,
    FlMethodCall* method_call,
    gpointer user_data) {
  (void)channel;
  (void)user_data;

  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  FlMethodResponse* resp = NULL;

  if (g_strcmp0(method, "addRoute") == 0) {
    const gchar* dest  = NULL;
    const gchar* gw    = NULL;
    const gchar* iface = NULL;
    if (args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* v;
      v = fl_value_lookup_string(args, "destinationCidr");
      if (v) dest = fl_value_get_string(v);
      v = fl_value_lookup_string(args, "gateway");
      if (v) gw = fl_value_get_string(v);
      v = fl_value_lookup_string(args, "interfaceName");
      if (v) iface = fl_value_get_string(v);
    }
    resp = handle_add_route(dest, gw, iface);
  } else if (g_strcmp0(method, "removeRoute") == 0) {
    const gchar* dest = NULL;
    if (args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* v = fl_value_lookup_string(args, "destinationCidr");
      if (v) dest = fl_value_get_string(v);
    }
    resp = handle_remove_route(dest);
  } else if (g_strcmp0(method, "enableSplitTunnel") == 0) {
    resp = handle_enable_split_tunnel(args);
  } else if (g_strcmp0(method, "disableSplitTunnel") == 0) {
    resp = handle_disable_split_tunnel();
  } else if (g_strcmp0(method, "getRoutes") == 0) {
    resp = handle_get_routes();
  } else if (g_strcmp0(method, "listInterfaces") == 0) {
    resp = handle_list_interfaces();
  } else {
    resp = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, resp, NULL);
  g_object_unref(resp);
}

/* ------------------------------------------------------------------ */
/*  Plugin registration                                                 */
/* ------------------------------------------------------------------ */
void route_manager_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  g_mutex_init(&g_routes_mutex);

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "com.medlinkconnect/route_manager",
      FL_METHOD_CODEC(codec));

  fl_method_channel_set_method_call_handler(
      channel, method_call_handler, NULL, NULL);
}
