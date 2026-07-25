#include "network_diagnostics_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar.h>
#include <flutter/standard_method_codec.h>

#include <glib.h>
#include <gio/gio.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <regex.h>
#include <unistd.h>

/* ------------------------------------------------------------------ */
/*  Helper: run a command synchronously and capture stdout / stderr    */
/* ------------------------------------------------------------------ */
static gboolean run_command(const gchar* cmd,
                            gchar**   stdout_out,
                            gchar**   stderr_out,
                            gint*     exit_code) {
  g_autoptr(GError) error = NULL;
  gboolean ok = g_spawn_command_line_sync(
      cmd,
      stdout_out,
      stderr_out,
      exit_code,
      &error);
  if (!ok) {
    if (stdout_out) *stdout_out = NULL;
    if (stderr_out) *stderr_out = g_strdup(error->message);
    if (exit_code)  *exit_code = -1;
  }
  return ok;
}

/* ------------------------------------------------------------------ */
/*  Helper: check whether the current process runs as root             */
/* ------------------------------------------------------------------ */
static gboolean is_root() {
  return geteuid() == 0;
}

/* ------------------------------------------------------------------ */
/*  flushDns                                                            */
/* ------------------------------------------------------------------ */
static FlMethodResponse* handle_flush_dns() {
  // Chain: resolvectl flush-caches → systemd-resolve --flush-caches
  //        → /etc/init.d/nscd restart
  g_autofree gchar* out = NULL;
  g_autofree gchar* err = NULL;
  gint exit_code = 0;
  g_autoptr(GString) msg = g_string_new("");

  // Try resolvectl first
  if (run_command("resolvectl flush-caches 2>&1", &out, &err, &exit_code) &&
      exit_code == 0) {
    g_string_append(msg, "DNS cache flushed via resolvectl.");
    return FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_string(msg->str)));
  }
  g_string_append(msg, "resolvectl: ");
  g_string_append(msg, err ? err : "not available");

  // Fallback to systemd-resolve
  g_free(out); out = NULL;
  g_free(err); err = NULL;
  if (run_command("systemd-resolve --flush-caches 2>&1", &out, &err, &exit_code) &&
      exit_code == 0) {
    g_string_append(msg, ". DNS cache flushed via systemd-resolve.");
    return FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_string(msg->str)));
  }
  g_string_append(msg, "; systemd-resolve: ");
  g_string_append(msg, err ? err : "not available");

  // Fallback to nscd restart
  g_free(out); out = NULL;
  g_free(err); err = NULL;
  if (run_command("/etc/init.d/nscd restart 2>&1", &out, &err, &exit_code) &&
      exit_code == 0) {
    g_string_append(msg, ". DNS cache flushed via nscd restart.");
    return FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_string(msg->str)));
  }
  // Even if nscd fails, we tried — report result
  g_string_append(msg, "; nscd: ");
  g_string_append(msg, err ? err : "not available");

  return FL_METHOD_RESPONSE(fl_method_success_response_new(
      fl_value_new_string(msg->str)));
}

/* ------------------------------------------------------------------ */
/*  clearNetworkCaches                                                  */
/* ------------------------------------------------------------------ */
static FlMethodResponse* handle_clear_network_caches() {
  if (!is_root()) {
    g_autofree gchar* err = g_strdup(
        "Se requieren privilegios de administrador para limpiar la caché ARP.");
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "permiso_denegado", err, nullptr));
  }

  g_autofree gchar* out = NULL;
  g_autofree gchar* err = NULL;
  gint exit_code = 0;

  if (!run_command("sudo ip neigh flush all 2>&1", &out, &err, &exit_code)) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "error_comando",
        err ? err : "Error al ejecutar ip neigh flush all",
        nullptr));
  }
  if (exit_code != 0) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "error_comando",
        err && *err ? err : "ip neigh flush all falló",
        nullptr));
  }

  return FL_METHOD_RESPONSE(fl_method_success_response_new(
      fl_value_new_string("Caché ARP limpiada exitosamente.")));
}

/* ------------------------------------------------------------------ */
/*  ping                                                                */
/* ------------------------------------------------------------------ */
static FlMethodResponse* handle_ping(const gchar* host) {
  if (!host || !*host) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "argumento_invalido", "Host no especificado", nullptr));
  }

  // Sanitise: only allow alphanumeric, dots, hyphens
  for (const gchar* p = host; *p; p++) {
    if (!g_ascii_isalnum(*p) && *p != '.' && *p != '-') {
      return FL_METHOD_RESPONSE(fl_method_error_response_new(
          "argumento_invalido", "Nombre de host inválido", nullptr));
    }
  }

  g_autofree gchar* cmd = g_strdup_printf(
      "ping -c 4 -W 2 %s 2>&1", host);
  g_autofree gchar* out = NULL;
  g_autofree gchar* err = NULL;
  gint exit_code = 0;

  if (!run_command(cmd, &out, &err, &exit_code)) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "inaccesible",
        err ? err : "No se pudo ejecutar ping",
        nullptr));
  }

  // Even if exit_code != 0, try to parse output (partial replies possible)
  const gchar* pattern = "rtt min/avg/max/mdev = "
                         "([0-9.]+)/([0-9.]+)/([0-9.]+)/([0-9.]+)";
  regex_t regex;
  regmatch_t matches[5];

  if (regcomp(&regex, pattern, REG_EXTENDED) != 0) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "inaccesible", "Error interno al compilar expresión regular", nullptr));
  }

  gint avg_ms = -1;
  if (out && regexec(&regex, out, 5, matches, 0) == 0) {
    // matches[2] is the avg group
    g_autofree gchar* avg_str = g_strndup(
        out + matches[2].rm_so,
        matches[2].rm_eo - matches[2].rm_so);
    avg_ms = (gint)(g_ascii_strtod(avg_str, NULL) + 0.5);
  }
  regfree(&regex);

  if (avg_ms < 0) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "inaccesible", "Host inaccesible", nullptr));
  }

  return FL_METHOD_RESPONSE(fl_method_success_response_new(
      fl_value_new_int(avg_ms)));
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

  if (g_strcmp0(method, "flushDns") == 0) {
    FlMethodResponse* resp = handle_flush_dns();
    fl_method_call_respond(method_call, resp, NULL);
    g_object_unref(resp);
    return;
  }

  if (g_strcmp0(method, "clearNetworkCaches") == 0) {
    FlMethodResponse* resp = handle_clear_network_caches();
    fl_method_call_respond(method_call, resp, NULL);
    g_object_unref(resp);
    return;
  }

  if (g_strcmp0(method, "ping") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    const gchar* host = NULL;
    if (args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* host_val = fl_value_lookup_string(args, "host");
      if (host_val && fl_value_get_type(host_val) == FL_VALUE_TYPE_STRING) {
        host = fl_value_get_string(host_val);
      }
    }
    FlMethodResponse* resp = handle_ping(host);
    fl_method_call_respond(method_call, resp, NULL);
    g_object_unref(resp);
    return;
  }

  fl_method_call_respond(
      method_call,
      FL_METHOD_RESPONSE(fl_method_not_implemented_response_new()),
      NULL);
}

/* ------------------------------------------------------------------ */
/*  Plugin registration                                                 */
/* ------------------------------------------------------------------ */
void network_diagnostics_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "com.medlinkconnect/network_diagnostics",
      FL_METHOD_CODEC(codec));

  fl_method_channel_set_method_call_handler(
      channel, method_call_handler, NULL, NULL);
}
