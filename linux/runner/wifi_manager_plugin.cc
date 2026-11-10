#include "wifi_manager_plugin.h"

#include <glib.h>
#include <glib/gstdio.h>
#include <unistd.h>

#include <algorithm>
#include <set>
#include <string>
#include <vector>

#include "async_method_call.h"
#include "process_utils.h"

namespace {

constexpr const char* kWifiUnavailable = "wifi_no_disponible";
constexpr const char* kInvalidArgument = "argumento_invalido";
constexpr const char* kPermissionDenied = "permiso_denegado";
constexpr const char* kCredentialsRequired = "credenciales_requeridas";
constexpr const char* kNetworkNotFound = "red_no_encontrada";
constexpr const char* kWifiError = "error_wifi";

FlMethodResponse* error_response(const char* code, const std::string& message) {
  return FL_METHOD_RESPONSE(
      fl_method_error_response_new(code, message.c_str(), nullptr));
}

std::string trim(const std::string& value) {
  const auto first = value.find_first_not_of(" \t\r\n");
  if (first == std::string::npos) return "";
  const auto last = value.find_last_not_of(" \t\r\n");
  return value.substr(first, last - first + 1);
}

bool has_control_chars(const std::string& value) {
  for (const unsigned char c : value) {
    if (c < 0x20 || c == 0x7f) return true;
  }
  return false;
}

bool valid_ssid(const std::string& ssid) {
  return !ssid.empty() && ssid.size() <= 32 && !has_control_chars(ssid);
}

bool nmcli_available() {
  g_autofree gchar* path = g_find_program_in_path("nmcli");
  return path != nullptr;
}

/**
 * Splits a terse (`-t`) nmcli line. nmcli escapes ':' and '\' with a
 * backslash, so a naive split would break SSIDs that contain colons.
 */
std::vector<std::string> split_terse_line(const std::string& line) {
  std::vector<std::string> fields;
  std::string current;
  bool escaped = false;

  for (const char c : line) {
    if (escaped) {
      current.push_back(c);
      escaped = false;
    } else if (c == '\\') {
      escaped = true;
    } else if (c == ':') {
      fields.push_back(current);
      current.clear();
    } else {
      current.push_back(c);
    }
  }
  if (escaped) current.push_back('\\');
  fields.push_back(current);
  return fields;
}

std::vector<std::string> split_lines(const gchar* output) {
  std::vector<std::string> lines;
  if (output == nullptr) return lines;
  g_auto(GStrv) parts = g_strsplit(output, "\n", -1);
  for (gchar** part = parts; part != nullptr && *part != nullptr; ++part) {
    lines.emplace_back(*part);
  }
  return lines;
}

gboolean run_nmcli(const std::vector<std::string>& args,
                   gchar** stdout_out,
                   gchar** stderr_out,
                   gint* exit_code) {
  std::vector<std::string> full_args{"nmcli"};
  full_args.insert(full_args.end(), args.begin(), args.end());
  return run_program(full_args, stdout_out, stderr_out, exit_code);
}

FlMethodResponse* nmcli_error_response(const gchar* stderr_text,
                                      const gchar* stdout_text,
                                      gint exit_code) {
  std::string detail = trim(stderr_text != nullptr ? stderr_text : "");
  if (detail.empty()) {
    detail = trim(stdout_text != nullptr ? stdout_text : "");
  }

  std::string lower = detail;
  std::transform(lower.begin(), lower.end(), lower.begin(),
                 [](unsigned char c) { return g_ascii_tolower(c); });

  if (lower.find("not authorized") != std::string::npos ||
      lower.find("not authorised") != std::string::npos ||
      lower.find("insufficient privileges") != std::string::npos ||
      lower.find("permission denied") != std::string::npos) {
    return error_response(
        kPermissionDenied,
        detail.empty()
            ? "NetworkManager no autorizó la operación Wi-Fi para este "
              "usuario."
            : detail);
  }

  if (lower.find("secrets were required") != std::string::npos ||
      lower.find("password") != std::string::npos) {
    return error_response(
        kCredentialsRequired,
        "La red Wi-Fi requiere una contraseña válida. Verifícala e inténtalo "
        "de nuevo.");
  }

  if (lower.find("no network with ssid") != std::string::npos) {
    return error_response(kNetworkNotFound,
                          "No se encontró la red Wi-Fi solicitada.");
  }

  if (detail.empty()) {
    detail = "nmcli terminó con código " + std::to_string(exit_code) + ".";
  }
  return error_response(kWifiError, detail);
}

FlMethodResponse* no_nmcli_response() {
  return error_response(
      kWifiUnavailable,
      "NetworkManager (nmcli) no está instalado. Instala NetworkManager para "
      "listar y conectar redes Wi-Fi desde la aplicación.");
}

std::string read_active_wifi_device() {
  g_autofree gchar* out = nullptr;
  g_autofree gchar* err = nullptr;
  gint exit_code = 0;

  if (!run_nmcli({"-t", "-f", "DEVICE,TYPE,STATE", "device", "status"}, &out,
                 &err, &exit_code) ||
      exit_code != 0) {
    return "";
  }

  for (const auto& line : split_lines(out)) {
    const auto fields = split_terse_line(line);
    if (fields.size() < 3) continue;
    if (fields[1] != "wifi") continue;
    if (fields[2].rfind("connected", 0) != 0) continue;
    return fields[0];
  }
  return "";
}

std::string read_active_ssid() {
  g_autofree gchar* out = nullptr;
  g_autofree gchar* err = nullptr;
  gint exit_code = 0;

  if (!run_nmcli({"-t", "-f", "IN-USE,SSID", "device", "wifi", "list"}, &out,
                 &err, &exit_code) ||
      exit_code != 0) {
    return "";
  }

  for (const auto& line : split_lines(out)) {
    const auto fields = split_terse_line(line);
    if (fields.size() < 2) continue;
    if (trim(fields[0]) == "*" && !fields[1].empty()) {
      return fields[1];
    }
  }
  return "";
}

std::string read_gateway(const std::string& device) {
  if (device.empty()) return "";

  g_autofree gchar* out = nullptr;
  g_autofree gchar* err = nullptr;
  gint exit_code = 0;

  if (!run_nmcli({"-t", "-f", "IP4.GATEWAY", "device", "show", device}, &out,
                 &err, &exit_code) ||
      exit_code != 0) {
    return "";
  }

  for (const auto& line : split_lines(out)) {
    const auto fields = split_terse_line(line);
    if (fields.size() < 2) continue;
    const std::string value = trim(fields[1]);
    if (!value.empty() && value != "--") return value;
  }
  return "";
}

FlMethodResponse* handle_get_current_info() {
  if (!nmcli_available()) return no_nmcli_response();

  const std::string device = read_active_wifi_device();
  std::string ssid;
  std::string gateway;
  if (!device.empty()) {
    ssid = read_active_ssid();
    gateway = read_gateway(device);
  }

  g_autoptr(FlValue) result = fl_value_new_map();
  fl_value_set_string_take(result, "ssid", fl_value_new_string(ssid.c_str()));
  fl_value_set_string_take(result, "interfaceName",
                           fl_value_new_string(device.c_str()));
  fl_value_set_string_take(result, "gateway",
                           fl_value_new_string(gateway.c_str()));

  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

FlMethodResponse* handle_scan_networks() {
  if (!nmcli_available()) return no_nmcli_response();

  g_autofree gchar* out = nullptr;
  g_autofree gchar* err = nullptr;
  gint exit_code = 0;

  gboolean ran = run_nmcli(
      {"-t", "-f", "SSID", "device", "wifi", "list", "--rescan", "yes"}, &out,
      &err, &exit_code);

  // NetworkManager rejects back-to-back rescans; the already cached list is
  // still useful in that case.
  if ((!ran || exit_code != 0) && err != nullptr &&
      g_strrstr(err, "Scanning not allowed") != nullptr) {
    g_free(out);
    out = nullptr;
    g_free(err);
    err = nullptr;
    ran = run_nmcli({"-t", "-f", "SSID", "device", "wifi", "list"}, &out,
                    &err, &exit_code);
  }

  if (!ran) {
    return error_response(kWifiUnavailable,
                          err != nullptr ? err : "No se pudo ejecutar nmcli.");
  }
  if (exit_code != 0) {
    return nmcli_error_response(err, out, exit_code);
  }

  g_autoptr(FlValue) networks = fl_value_new_list();
  std::set<std::string> seen;
  for (const auto& line : split_lines(out)) {
    if (line.empty()) continue;
    const auto fields = split_terse_line(line);
    if (fields.empty() || fields[0].empty()) continue;

    const std::string& ssid = fields[0];
    if (seen.insert(ssid).second) {
      fl_value_append_take(networks, fl_value_new_string(ssid.c_str()));
    }
  }

  return FL_METHOD_RESPONSE(fl_method_success_response_new(networks));
}

FlMethodResponse* connect_open_network(const std::string& ssid) {
  g_autofree gchar* out = nullptr;
  g_autofree gchar* err = nullptr;
  gint exit_code = 0;
  const gboolean ran =
      run_nmcli({"--wait", "20", "device", "wifi", "connect", ssid}, &out,
                &err, &exit_code);

  if (!ran) {
    return error_response(kWifiUnavailable,
                          err != nullptr ? err : "No se pudo ejecutar nmcli.");
  }
  if (exit_code != 0) {
    return nmcli_error_response(err, out, exit_code);
  }
  return nullptr;
}

FlMethodResponse* connect_secured_network(const std::string& ssid,
                                          const std::string& password) {
  gchar* temp_path = nullptr;
  GError* error = nullptr;
  const gint fd = g_file_open_tmp("medlink-wifi-XXXXXX", &temp_path, &error);
  if (fd < 0) {
    const std::string detail =
        error != nullptr ? error->message : "desconocido";
    g_clear_error(&error);
    g_free(temp_path);
    return error_response(
        kWifiError,
        "No se pudo preparar el archivo temporal de credenciales: " + detail);
  }

  const std::string contents =
      "802-11-wireless-security.psk:" + password + "\n";
  const ssize_t written = write(fd, contents.data(), contents.size());
  close(fd);
  if (written != static_cast<ssize_t>(contents.size())) {
    g_remove(temp_path);
    g_free(temp_path);
    return error_response(
        kWifiError,
        "No se pudieron escribir las credenciales Wi-Fi en el archivo "
        "temporal.");
  }

  auto cleanup = [&]() {
    g_remove(temp_path);
    g_free(temp_path);
    temp_path = nullptr;
  };

  auto try_up = [&](const std::string& profile_id, gchar** out,
                    gchar** err, gint* code) {
    return run_nmcli({"--wait", "20", "connection", "up", "id", profile_id,
                      "passwd-file", temp_path},
                     out, err, code);
  };

  g_autofree gchar* out = nullptr;
  g_autofree gchar* err = nullptr;
  gint exit_code = 0;
  gboolean ran = try_up(ssid, &out, &err, &exit_code);

  if (ran && exit_code == 0) {
    cleanup();
    g_autofree gchar* message =
        g_strdup_printf("Conectado a la red Wi-Fi \"%s\".", ssid.c_str());
    return FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_string(message)));
  }

  const std::string profile_id = "medlink-" + ssid;
  g_clear_pointer(&out, g_free);
  g_clear_pointer(&err, g_free);
  exit_code = 0;
  ran = run_nmcli({"--wait", "20", "connection", "add", "type", "wifi",
                   "con-name", profile_id, "ssid", ssid,
                   "wifi-sec.key-mgmt", "wpa-psk"},
                  &out, &err, &exit_code);

  if (!ran) {
    cleanup();
    return error_response(kWifiUnavailable,
                          err != nullptr ? err : "No se pudo ejecutar nmcli.");
  }

  // The profile may already exist from a previous session; in that case the
  // add command fails but activating it with the supplied password still
  // works, so retry `up` regardless of the add result.
  g_clear_pointer(&out, g_free);
  g_clear_pointer(&err, g_free);
  exit_code = 0;
  ran = try_up(profile_id, &out, &err, &exit_code);

  if (!ran) {
    cleanup();
    return error_response(kWifiUnavailable,
                          err != nullptr ? err : "No se pudo ejecutar nmcli.");
  }
  if (exit_code != 0) {
    FlMethodResponse* response = nmcli_error_response(err, out, exit_code);
    cleanup();
    return response;
  }

  cleanup();
  g_autofree gchar* message =
      g_strdup_printf("Conectado a la red Wi-Fi \"%s\".", ssid.c_str());
  return FL_METHOD_RESPONSE(fl_method_success_response_new(
      fl_value_new_string(message)));
}

FlMethodResponse* handle_connect(const std::string& ssid,
                                 const std::string& password) {
  if (!valid_ssid(ssid)) {
    return error_response(
        kInvalidArgument,
        "El nombre de la red Wi-Fi no es válido o supera los 32 caracteres.");
  }
  if (has_control_chars(password)) {
    return error_response(kInvalidArgument,
                          "La contraseña Wi-Fi contiene caracteres inválidos.");
  }
  if (!nmcli_available()) return no_nmcli_response();

  if (password.empty()) {
    FlMethodResponse* response = connect_open_network(ssid);
    if (response != nullptr) return response;
  } else {
    FlMethodResponse* response = connect_secured_network(ssid, password);
    if (response != nullptr) return response;
  }

  g_autofree gchar* message =
      g_strdup_printf("Conectado a la red Wi-Fi \"%s\".", ssid.c_str());
  return FL_METHOD_RESPONSE(fl_method_success_response_new(
      fl_value_new_string(message)));
}

void method_call_handler(FlMethodChannel* channel,
                         FlMethodCall* method_call,
                         gpointer user_data) {
  (void)channel;
  (void)user_data;

  const gchar* method = fl_method_call_get_name(method_call);

  if (g_strcmp0(method, "scanNetworks") == 0) {
    respond_async(method_call, [] { return handle_scan_networks(); });
    return;
  }

  if (g_strcmp0(method, "getCurrentInfo") == 0) {
    respond_async(method_call, [] { return handle_get_current_info(); });
    return;
  }

  if (g_strcmp0(method, "connect") == 0) {
    std::string ssid;
    std::string password;
    FlValue* args = fl_method_call_get_args(method_call);
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* ssid_value = fl_value_lookup_string(args, "ssid");
      FlValue* password_value = fl_value_lookup_string(args, "password");
      if (ssid_value != nullptr &&
          fl_value_get_type(ssid_value) == FL_VALUE_TYPE_STRING) {
        ssid = fl_value_get_string(ssid_value);
      }
      if (password_value != nullptr &&
          fl_value_get_type(password_value) == FL_VALUE_TYPE_STRING) {
        password = fl_value_get_string(password_value);
      }
    }

    respond_async(method_call, [ssid, password] {
      return handle_connect(ssid, password);
    });
    return;
  }

  fl_method_call_respond(
      method_call,
      FL_METHOD_RESPONSE(fl_method_not_implemented_response_new()), nullptr);
}

}  // namespace

void wifi_manager_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "com.medlinkconnect/wifi_manager", FL_METHOD_CODEC(codec));

  fl_method_channel_set_method_call_handler(channel, method_call_handler,
                                            nullptr, nullptr);
}
