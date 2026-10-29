#include "rdp_launcher_plugin.h"

#include <glib.h>

#include <string>

#include "process_utils.h"

namespace {

bool binary_in_path(const gchar* name) {
  g_autofree gchar* path = g_find_program_in_path(name);
  return path != nullptr;
}

bool scheme_handler_exists(const gchar* scheme) {
  g_autofree gchar* key =
      g_strdup_printf("x-scheme-handler/%s", scheme);
  gchar* out = nullptr;
  gchar* err = nullptr;
  gint exit_code = 0;
  const gboolean ran =
      run_program({"xdg-mime", "query", "default", key}, &out, &err,
                  &exit_code);
  const bool found = ran && exit_code == 0 && out && *out;
  g_free(out);
  g_free(err);
  return found;
}

bool has_control_chars(const gchar* value) {
  if (!value) return false;
  for (const guchar* p = reinterpret_cast<const guchar*>(value); *p; ++p) {
    if (*p < 0x20 || *p == 0x7f) return true;
  }
  return false;
}

FlMethodResponse* error_response(const gchar* code, const std::string& message) {
  return FL_METHOD_RESPONSE(
      fl_method_error_response_new(code, message.c_str(), nullptr));
}

FlMethodResponse* handle_pre_launch() {
  if (!binary_in_path("xdg-open")) {
    return error_response("xdg_open_faltante",
                          "xdg-open no está disponible en el sistema.");
  }
  if (scheme_handler_exists("rdp") ||
      scheme_handler_exists("ms-rd-web")) {
    return FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_bool(TRUE)));
  }
  return error_response("sin_manejador_rdp",
                        "No se encontró un manejador para rdp:// ni "
                        "ms-rd-web://.");
}

FlMethodResponse* handle_launch_rdp(FlValue* args) {
  if (!args || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return error_response("argumento_invalido",
                          "Se requiere un mapa de argumentos.");
  }

  FlValue* host_val = fl_value_lookup_string(args, "host");
  FlValue* port_val = fl_value_lookup_string(args, "port");
  FlValue* user_val = fl_value_lookup_string(args, "username");
  FlValue* dom_val = fl_value_lookup_string(args, "domain");
  FlValue* web_val = fl_value_lookup_string(args, "useWebFeed");

  if (!host_val || fl_value_get_type(host_val) != FL_VALUE_TYPE_STRING ||
      has_control_chars(fl_value_get_string(host_val))) {
    return error_response("argumento_invalido",
                          "Falta el parámetro 'host' o es inválido.");
  }

  const gchar* host = fl_value_get_string(host_val);
  if (!host || !*host) {
    return error_response("argumento_invalido", "El host no puede estar vacío.");
  }

  gint port = 3389;
  if (port_val && fl_value_get_type(port_val) == FL_VALUE_TYPE_INT) {
    port = fl_value_get_int(port_val);
  }
  if (port <= 0 || port > 65535) {
    return error_response("argumento_invalido", "Puerto RDP inválido.");
  }

  const gchar* username =
      (user_val && fl_value_get_type(user_val) == FL_VALUE_TYPE_STRING)
          ? fl_value_get_string(user_val)
          : nullptr;
  const gchar* domain =
      (dom_val && fl_value_get_type(dom_val) == FL_VALUE_TYPE_STRING)
          ? fl_value_get_string(dom_val)
          : nullptr;
  if (has_control_chars(username) || has_control_chars(domain)) {
    return error_response("argumento_invalido",
                          "Usuario o dominio contienen caracteres inválidos.");
  }

  gboolean use_web = FALSE;
  if (web_val && fl_value_get_type(web_val) == FL_VALUE_TYPE_BOOL) {
    use_web = fl_value_get_bool(web_val);
  }

  g_autofree gchar* encoded_host =
      g_uri_escape_string(host, nullptr, FALSE);
  g_autoptr(GString) uri = g_string_new(use_web ? "ms-rd-web://" : "rdp://");

  if (!use_web) {
    g_autoptr(GString) authority = g_string_new("");
    if (domain && *domain) {
      g_string_append(authority, domain);
      g_string_append_c(authority, '\\');
    }
    if (username && *username) {
      g_string_append(authority, username);
    }
    if (authority->len > 0) {
      g_autofree gchar* encoded_auth =
          g_uri_escape_string(authority->str, nullptr, FALSE);
      g_string_append(uri, encoded_auth ? encoded_auth : authority->str);
      g_string_append_c(uri, '@');
    }
    g_string_append_printf(uri, "%s:%d", encoded_host, port);
  } else {
    g_string_append(uri, encoded_host);
  }

  g_autofree gchar* out = nullptr;
  g_autofree gchar* err = nullptr;
  gint exit_code = 0;
  const gboolean ran =
      run_program({"xdg-open", uri->str}, &out, &err, &exit_code);
  if (!ran || exit_code != 0) {
    const std::string detail = err && *err ? err : "desconocido";
    return error_response("lanzamiento_fallido",
                          "No se pudo lanzar el cliente RDP: " + detail);
  }

  g_autofree gchar* ok_msg = g_strdup_printf(
      "Conexión RDP lanzada a %s:%d correctamente.", host, port);
  return FL_METHOD_RESPONSE(
      fl_method_success_response_new(fl_value_new_string(ok_msg)));
}

FlMethodResponse* handle_is_rdp_client_available() {
  if (binary_in_path("remmina") || binary_in_path("xfreerdp") ||
      binary_in_path("mstsc") || scheme_handler_exists("rdp") ||
      scheme_handler_exists("ms-rd-web")) {
    return FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_bool(TRUE)));
  }
  return FL_METHOD_RESPONSE(
      fl_method_success_response_new(fl_value_new_bool(FALSE)));
}

void method_call_handler(FlMethodChannel* channel,
                         FlMethodCall* method_call,
                         gpointer user_data) {
  (void)channel;
  (void)user_data;

  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);
  FlMethodResponse* response = nullptr;

  if (g_strcmp0(method, "preLaunch") == 0) {
    response = handle_pre_launch();
  } else if (g_strcmp0(method, "isRdpClientAvailable") == 0) {
    response = handle_is_rdp_client_available();
  } else if (g_strcmp0(method, "launchRdp") == 0) {
    response = handle_launch_rdp(args);
  } else {
    response =
        FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
  g_object_unref(response);
}

}  // namespace

void rdp_launcher_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "com.medlinkconnect/rdp_launcher", FL_METHOD_CODEC(codec));

  fl_method_channel_set_method_call_handler(channel, method_call_handler,
                                            nullptr, nullptr);
}
