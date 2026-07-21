#include <flutter_linux/flutter_linux.h>

#include <cstdlib>
#include <cstdio>
#include <cstring>
#include <memory>
#include <string>
#include <regex>
#include <unistd.h>

#include "network_diagnostics_plugin.h"

// ── helpers ────────────────────────────────────────────────────────────────

namespace {

/// Run a shell command and capture stdout+stderr.
/// Returns {output, exit_code}.
std::pair<std::string, int> RunCommand(const std::string& command) {
  // Append stderr redirect
  std::string full_cmd = command + " 2>&1";
  FILE* pipe = popen(full_cmd.c_str(), "r");
  if (!pipe) {
    return {"Failed to run command", -1};
  }

  std::string output;
  char buffer[4096];
  while (fgets(buffer, sizeof(buffer), pipe) != nullptr) {
    output += buffer;
  }

  int status = pclose(pipe);
  int exit_code = WEXITSTATUS(status);

  return {output, exit_code};
}

bool IsElevated() {
  return getuid() == 0;
}

}  // namespace

// ── plugin impl ────────────────────────────────────────────────────────────

struct _NetworkDiagnosticsPlugin {
  GObject parent_instance;

  FlMethodChannel* channel;
};

G_DEFINE_TYPE(NetworkDiagnosticsPlugin, network_diagnostics_plugin, G_TYPE_OBJECT)

// Forward declarations
static void network_diagnostics_plugin_handle_method_call(
    NetworkDiagnosticsPlugin* self,
    FlMethodCall* method_call);

// ── method dispatchers ─────────────────────────────────────────────────────

static void handle_flush_dns(NetworkDiagnosticsPlugin* self,
                             FlMethodCall* method_call) {
  g_autoptr(FlMethodResponse) response = nullptr;

  if (!IsElevated()) {
    response = FL_METHOD_RESPONSE(fl_method_error_response_new(
        "elevation_required",
        "Elevation required: DNS flush needs root privileges. Run with sudo.",
        nullptr));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  // Linux: try resolvectl first, then systemd-resolve, then nscd
  auto [out1, code1] = RunCommand("resolvectl flush-caches");
  if (code1 == 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_bool(TRUE)));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  // Fallback 1: systemd-resolve
  auto [out2, code2] = RunCommand("systemd-resolve --flush-caches");
  if (code2 == 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_bool(TRUE)));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  // Fallback 2: nscd restart
  auto [out3, code3] = RunCommand("/etc/init.d/nscd restart");
  bool ok = (code1 == 0 || code2 == 0 || code3 == 0);
  response = FL_METHOD_RESPONSE(fl_method_success_response_new(
      fl_value_new_bool(ok ? TRUE : FALSE)));
  fl_method_call_respond(method_call, response, nullptr);
}

static void handle_clear_caches(NetworkDiagnosticsPlugin* self,
                                FlMethodCall* method_call) {
  g_autoptr(FlMethodResponse) response = nullptr;

  if (!IsElevated()) {
    response = FL_METHOD_RESPONSE(fl_method_error_response_new(
        "elevation_required",
        "Elevation required: ARP cache clear needs root privileges. Run with sudo.",
        nullptr));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  auto [output, exit_code] = RunCommand("ip neigh flush all");
  // Even if exit_code != 0, partial success is OK
  bool ok = (exit_code == 0);
  response = FL_METHOD_RESPONSE(fl_method_success_response_new(
      fl_value_new_bool(ok ? TRUE : FALSE)));
  fl_method_call_respond(method_call, response, nullptr);
}

static void handle_ping(NetworkDiagnosticsPlugin* self,
                        FlMethodCall* method_call) {
  g_autoptr(FlMethodResponse) response = nullptr;

  FlValue* args = fl_method_call_get_args(method_call);
  if (!args || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    response = FL_METHOD_RESPONSE(fl_method_error_response_new(
        "bad_arguments", "Expected a map with 'host', 'count', 'timeoutMs'.", nullptr));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  // Extract arguments with defaults
  const char* host = "8.8.8.8";
  int count = 4;
  int timeout_sec = 2;

  FlValue* host_val = fl_value_lookup_string(args, "host");
  if (host_val && fl_value_get_type(host_val) == FL_VALUE_TYPE_STRING) {
    host = fl_value_get_string(host_val);
  }

  FlValue* count_val = fl_value_lookup_string(args, "count");
  if (count_val && fl_value_get_type(count_val) == FL_VALUE_TYPE_INT) {
    count = fl_value_get_int(count_val);
  }

  FlValue* to_val = fl_value_lookup_string(args, "timeoutMs");
  if (to_val && fl_value_get_type(to_val) == FL_VALUE_TYPE_INT) {
    timeout_sec = std::max(1, fl_value_get_int(to_val) / 1000);
  }

  char cmd[512];
  snprintf(cmd, sizeof(cmd), "ping -c %d -W %d %s", count, timeout_sec, host);

  auto [output, exit_code] = RunCommand(cmd);

  if (exit_code != 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  // Parse: "rtt min/avg/max/mdev = X/Y/Z/W ms"
  std::regex rtt_re(
      R"((?:round-trip|rtt)\s+min/avg/max/(?:mdev|stddev)\s*=\s*([\d.]+)/([\d.]+)/([\d.]+)/([\d.]+)\s*ms)",
      std::regex::icase);
  std::smatch match;
  if (std::regex_search(output, match, rtt_re)) {
    double avg = std::stod(match[2].str());
    int avg_ms = static_cast<int>(std::round(avg));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_int(avg_ms)));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }

  fl_method_call_respond(method_call, response, nullptr);
}

// ── GObject boilerplate ────────────────────────────────────────────────────

static void network_diagnostics_plugin_dispose(GObject* object) {
  NetworkDiagnosticsPlugin* self = NETWORK_DIAGNOSTICS_PLUGIN(object);
  g_clear_object(&self->channel);
  G_OBJECT_CLASS(network_diagnostics_plugin_parent_class)->dispose(object);
}

static void network_diagnostics_plugin_class_init(
    NetworkDiagnosticsPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = network_diagnostics_plugin_dispose;
}

static void network_diagnostics_plugin_init(NetworkDiagnosticsPlugin* self) {}

static void network_diagnostics_plugin_handle_method_call(
    NetworkDiagnosticsPlugin* self,
    FlMethodCall* method_call) {
  const gchar* method = fl_method_call_get_name(method_call);

  if (g_strcmp0(method, "flushDns") == 0) {
    handle_flush_dns(self, method_call);
  } else if (g_strcmp0(method, "clearNetworkCaches") == 0) {
    handle_clear_caches(self, method_call);
  } else if (g_strcmp0(method, "ping") == 0) {
    handle_ping(self, method_call);
  } else {
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    fl_method_call_respond(method_call, response, nullptr);
  }
}

// ── public registrar ───────────────────────────────────────────────────────

void network_diagnostics_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  NetworkDiagnosticsPlugin* plugin = NETWORK_DIAGNOSTICS_PLUGIN(
      g_object_new(network_diagnostics_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  plugin->channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "com.medlinkconnect/network_diagnostics",
      FL_METHOD_CODEC(codec));

  fl_method_channel_set_method_call_handler(
      plugin->channel,
      [](FlMethodChannel* channel, FlMethodCall* call, gpointer user_data) {
        auto* self = static_cast<NetworkDiagnosticsPlugin*>(user_data);
        network_diagnostics_plugin_handle_method_call(self, call);
      },
      plugin,
      nullptr);

  g_object_unref(plugin);
}
