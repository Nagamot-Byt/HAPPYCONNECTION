#include "network_diagnostics_plugin.h"

#include <glib.h>
#include <gio/gio.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <regex.h>
#include <sys/socket.h>
#include <netdb.h>
#include <fcntl.h>
#include <errno.h>
#include <unistd.h>

#include "async_method_call.h"
#include "process_utils.h"

#include <string>

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
  if (run_program({"resolvectl", "flush-caches"}, &out, &err, &exit_code) &&
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
  if (run_program({"systemd-resolve", "--flush-caches"}, &out, &err,
                  &exit_code) &&
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
  if (run_privileged({"/etc/init.d/nscd", "restart"}, &out, &err,
                     &exit_code) &&
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
  g_autofree gchar* out = NULL;
  g_autofree gchar* err = NULL;
  gint exit_code = 0;

  if (!run_privileged({"ip", "neigh", "flush", "all"}, &out, &err,
                      &exit_code)) {
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

  g_autofree gchar* out = NULL;
  g_autofree gchar* err = NULL;
  gint exit_code = 0;

  if (!run_program({"ping", "-c", "4", "-W", "2", host}, &out, &err,
                   &exit_code)) {
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
/*  checkTcpPort                                                       */
/* ------------------------------------------------------------------ */
static FlMethodResponse* handle_check_tcp_port(const gchar* host, gint port) {
  if (!host || !*host || port <= 0 || port > 65535) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "argumento_invalido", "Host o puerto inválido", nullptr));
  }

  struct addrinfo hints;
  memset(&hints, 0, sizeof(hints));
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_family = AF_UNSPEC;

  gchar port_str[16];
  g_snprintf(port_str, sizeof(port_str), "%d", port);

  struct addrinfo* result = NULL;
  if (getaddrinfo(host, port_str, &hints, &result) != 0 || result == NULL) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "inaccesible", "No se pudo resolver el host", nullptr));
  }

  gint elapsed_ms = -1;
  for (struct addrinfo* rp = result; rp != NULL; rp = rp->ai_next) {
    int fd = socket(rp->ai_family, rp->ai_socktype, rp->ai_protocol);
    if (fd < 0) continue;

    int flags = fcntl(fd, F_GETFL, 0);
    if (flags >= 0) {
      fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    }

    gint64 start_us = g_get_monotonic_time();
    int conn = connect(fd, rp->ai_addr, rp->ai_addrlen);
    if (conn == 0) {
      elapsed_ms = (gint)((g_get_monotonic_time() - start_us) / 1000);
      close(fd);
      break;
    }
    if (errno == EINPROGRESS) {
      fd_set writefds;
      FD_ZERO(&writefds);
      FD_SET(fd, &writefds);
      struct timeval timeout;
      timeout.tv_sec = 1;
      timeout.tv_usec = 500000;
      int sel = select(fd + 1, NULL, &writefds, NULL, &timeout);
      if (sel > 0 && FD_ISSET(fd, &writefds)) {
        int so_error = 0;
        socklen_t len = sizeof(so_error);
        if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &so_error, &len) == 0 &&
            so_error == 0) {
          elapsed_ms = (gint)((g_get_monotonic_time() - start_us) / 1000);
          close(fd);
          break;
        }
      }
    }
    close(fd);
  }

  freeaddrinfo(result);

  if (elapsed_ms < 0) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "inaccesible",
        "No se pudo establecer conexión TCP con el puerto",
        nullptr));
  }

  return FL_METHOD_RESPONSE(fl_method_success_response_new(
      fl_value_new_int(elapsed_ms)));
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
    respond_async(method_call, [] { return handle_flush_dns(); });
    return;
  }

  if (g_strcmp0(method, "clearNetworkCaches") == 0) {
    respond_async(method_call, [] { return handle_clear_network_caches(); });
    return;
  }

  if (g_strcmp0(method, "ping") == 0) {
    std::string host;
    FlValue* args = fl_method_call_get_args(method_call);
    if (args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* host_val = fl_value_lookup_string(args, "host");
      if (host_val && fl_value_get_type(host_val) == FL_VALUE_TYPE_STRING) {
        host = fl_value_get_string(host_val);
      }
    }
    respond_async(method_call,
                  [host] { return handle_ping(host.c_str()); });
    return;
  }

  if (g_strcmp0(method, "checkTcpPort") == 0) {
    std::string host;
    gint port = 0;
    FlValue* args = fl_method_call_get_args(method_call);
    if (args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* host_val = fl_value_lookup_string(args, "host");
      FlValue* port_val = fl_value_lookup_string(args, "port");
      if (host_val && fl_value_get_type(host_val) == FL_VALUE_TYPE_STRING) {
        host = fl_value_get_string(host_val);
      }
      if (port_val && fl_value_get_type(port_val) == FL_VALUE_TYPE_INT) {
        port = fl_value_get_int(port_val);
      }
    }
    respond_async(method_call,
                  [host, port] { return handle_check_tcp_port(host.c_str(), port); });
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
