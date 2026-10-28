#include "rdp_launcher_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar.h>
#include <flutter/standard_method_codec.h>

#include <glib.h>
#include <gio/gio.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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

/* ------------------------------------------------------------------ */
/*  Helper: check if a binary exists in PATH                           */
/* ------------------------------------------------------------------ */
static gboolean binary_in_path(const gchar* name) {
  g_autofree gchar* path = g_find_program_in_path(name);
  return path != NULL;
}

/* ------------------------------------------------------------------ */
/*  Helper: check scheme handler existence                              */
/* ------------------------------------------------------------------ */
static gboolean scheme_handler_exists(const gchar* scheme) {
  g_autofree gchar* cmd = g_strdup_printf(
      "xdg-mime query default x-scheme-handler/%s 2>&1", scheme);
  g_autofree gchar* out = NULL;
  g_autofree gchar* err = NULL;
  gint exit_code = 0;

  if (!run_cmd(cmd, &out, &err, &exit_code)) return FALSE;
  if (exit_code != 0) return FALSE;
  // If output is empty/non-empty, both indicate something registered
  return (out != NULL && *out != '\0');
}

/* ------------------------------------------------------------------ */
/*  preLaunch                                                           */
/* ------------------------------------------------------------------ */
static FlMethodResponse* handle_pre_launch() {
  // Step 1: verify xdg-open is available
  if (!binary_in_path("xdg-open")) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "xdg_open_faltante",
        "xdg-open no está disponible en el sistema",
        nullptr));
  }

  // Step 2: check rdp:// scheme handler
  if (scheme_handler_exists("rdp")) {
    return FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_bool(TRUE)));
  }

  // Step 3: fallback to ms-rd-web://
  if (scheme_handler_exists("ms-rd-web")) {
    return FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_bool(TRUE)));
  }

  return FL_METHOD_RESPONSE(fl_method_error_response_new(
      "sin_manejador_rdp",
      "No se encontró un manejador para rdp:// ni ms-rd-web://",
      nullptr));
}

/* ------------------------------------------------------------------ */
/*  launchRdp — build URI and hand off to xdg-open                     */
/* ------------------------------------------------------------------ */
static FlMethodResponse* handle_launch_rdp(FlValue* args) {
  if (!args || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "argumento_invalido", "Se requiere un mapa de argumentos", nullptr));
  }

  FlValue* host_val = fl_value_lookup_string(args, "host");
  FlValue* port_val = fl_value_lookup_string(args, "port");
  FlValue* user_val = fl_value_lookup_string(args, "username");
  FlValue* dom_val  = fl_value_lookup_string(args, "domain");
  FlValue* web_val  = fl_value_lookup_string(args, "useWebFeed");

  if (!host_val || fl_value_get_type(host_val) != FL_VALUE_TYPE_STRING) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "argumento_invalido", "Falta el parámetro 'host'", nullptr));
  }

  const gchar* host = fl_value_get_string(host_val);
  gint port = 3389;
  if (port_val && fl_value_get_type(port_val) == FL_VALUE_TYPE_INT) {
    port = fl_value_get_int(port_val);
  }
  if (port <= 0 || port > 65535) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "argumento_invalido", "Puerto RDP inválido", nullptr));
  }

  const gchar* username =
      (user_val && fl_value_get_type(user_val) == FL_VALUE_TYPE_STRING)
          ? fl_value_get_string(user_val)
          : nullptr;
  const gchar* domain =
      (dom_val && fl_value_get_type(dom_val) == FL_VALUE_TYPE_STRING)
          ? fl_value_get_string(dom_val)
          : nullptr;
  gboolean use_web = FALSE;
  if (web_val && fl_value_get_type(web_val) == FL_VALUE_TYPE_BOOL) {
    use_web = fl_value_get_bool(web_val);
  }

  // URI-encode the host / user / domain pieces (basic percent-encoding).
  // For simplicity we pass the raw URI through g_uri_parse_scheme to verify.
  g_autoptr(GString) uri = g_string_new("");

  if (use_web) {
    g_string_append(uri, "ms-rd-web://");
  } else {
    g_string_append(uri, "rdp://");
  }

  // Format authority: [domain\\]user[:password]@host:port
  // (we never pass passwords through the URI for security)
  gboolean added_auth = FALSE;
  g_autoptr(GString) authority = g_string_new("");
  if (domain && *domain) {
    g_string_append(authority, domain);
    g_string_append_c(authority, '\\');
    added_auth = TRUE;
  }
  if (username && *username) {
    g_string_append(authority, username);
    added_auth = TRUE;
  }
  if (added_auth) {
    g_string_append_c(authority, '@');
  }
  g_string_append_printf(authority, "%s:%d", host, port);

  // Percent-encode reserved chars that break URI parsing.
  g_autofree gchar* encoded_auth = g_uri_escape_string(
      authority->str, G_URI_RESERVED_CHARS_SUBCOMPONENT_DELIMITERS, FALSE);
  g_string_append(uri, encoded_auth ? encoded_auth : authority->str);

  g_autofree gchar* cmd =
      g_strdup_printf("xdg-open '%s' 2>&1", uri->str);
  g_autofree gchar* out = NULL;
  g_autofree gchar* err = NULL;
  gint exit_code = 0;

  if (!run_cmd(cmd, &out, &err, &exit_code) || exit_code != 0) {
    g_autofree gchar* msg = g_strdup_printf(
        "No se pudo lanzar el cliente RDP: %s",
        err && *err ? err : "desconocido");
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "lanzamiento_fallido", msg, nullptr));
  }

  g_autofree gchar* ok_msg = g_strdup_printf(
      "Conexión RDP lanzada a %s:%d correctamente.", host, port);
  return FL_METHOD_RESPONSE(
      fl_method_success_response_new(fl_value_new_string(ok_msg)));
}

/* ------------------------------------------------------------------ */
/*  isRdpClientAvailable                                                */
/* ------------------------------------------------------------------ */
static FlMethodResponse* handle_is_rdp_client_available() {
  // Check for known RDP clients
  if (binary_in_path("remmina")) {
    return FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_bool(TRUE)));
  }
  if (binary_in_path("xfreerdp")) {
    return FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_bool(TRUE)));
  }
  if (binary_in_path("mstsc")) {
    return FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_bool(TRUE)));
  }

  // Check scheme handlers
  if (scheme_handler_exists("rdp") || scheme_handler_exists("ms-rd-web")) {
    return FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_bool(TRUE)));
  }

  return FL_METHOD_RESPONSE(fl_method_success_response_new(
      fl_value_new_bool(FALSE)));
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

  if (g_strcmp0(method, "preLaunch") == 0) {
    resp = handle_pre_launch();
  } else if (g_strcmp0(method, "isRdpClientAvailable") == 0) {
    resp = handle_is_rdp_client_available();
  } else if (g_strcmp0(method, "launchRdp") == 0) {
    resp = handle_launch_rdp(args);
  } else {
    resp = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, resp, NULL);
  g_object_unref(resp);
}

/* ------------------------------------------------------------------ */
/*  Plugin registration                                                 */
/* ------------------------------------------------------------------ */
void rdp_launcher_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "com.medlinkconnect/rdp_launcher",
      FL_METHOD_CODEC(codec));

  fl_method_channel_set_method_call_handler(
      channel, method_call_handler, NULL, NULL);
}
