#include "route_manager_plugin.h"

#include <flutter_windows.h>
#include <winsock2.h>
#include <iphlpapi.h>
#include <stdio.h>
#include <stdlib.h>
#pragma comment(lib, "iphlpapi.lib")
#pragma comment(lib, "ws2_32.lib")

static GList* g_tracked_routes = NULL;
static GMutex g_routes_mutex;

/* ------------------------------------------------------------------ */
/*  addRoute — netsh interface ip add route                             */
/* ------------------------------------------------------------------ */
static FlMethodResponse* HandleAddRoute(
    const gchar* dest_cidr,
    const gchar* gateway,
    const gchar* interface_name) {
  if (!dest_cidr || !gateway || !interface_name) {
    g_autofree gchar* msg = g_strdup("Missing parameters");
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "invalid_args", msg, nullptr));
  }

  g_autofree gchar* cmd = g_strdup_printf(
      "netsh interface ip add route %s %s %s",
      dest_cidr, gateway, interface_name);

  // Execute command (simplified; real impl would use ShellExecute)
  int result = system(cmd);

  if (result != 0) {
    g_autofree gchar* msg = g_strdup_printf(
        "Failed to add route: %s", dest_cidr);
    g_autoptr(FlValue) response_map = fl_value_new_map();
    fl_value_append_string(response_map, "success", fl_value_new_bool(FALSE));
    fl_value_append_string(response_map, "message", fl_value_new_string(msg));
    return FL_METHOD_RESPONSE(fl_method_success_response_new(response_map));
  }

  g_autoptr(FlValue) response_map = fl_value_new_map();
  fl_value_append_string(response_map, "success", fl_value_new_bool(TRUE));
  fl_value_append_string(response_map, "message",
      fl_value_new_string("Route added successfully"));
  return FL_METHOD_RESPONSE(fl_method_success_response_new(response_map));
}

/* ------------------------------------------------------------------ */
/*  removeRoute — netsh interface ip delete route                       */
/* ------------------------------------------------------------------ */
static FlMethodResponse* HandleRemoveRoute(const gchar* dest_cidr) {
  if (!dest_cidr) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "invalid_args", "Missing destinationCidr", nullptr));
  }

  g_autofree gchar* cmd = g_strdup_printf(
      "netsh interface ip delete route %s", dest_cidr);

  int result = system(cmd);

  g_autoptr(FlValue) response_map = fl_value_new_map();
  fl_value_append_string(response_map, "success",
      fl_value_new_bool(result == 0));
  fl_value_append_string(response_map, "message",
      fl_value_new_string(result == 0 ? "Route removed" : "Failed to remove route"));
  return FL_METHOD_RESPONSE(fl_method_success_response_new(response_map));
}

/* ------------------------------------------------------------------ */
/*  enableSplitTunnel — add all hospital subnets                        */
/* ------------------------------------------------------------------ */
static FlMethodResponse* HandleEnableSplitTunnel(FlValue* args) {
  if (!args || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "invalid_args", "Invalid arguments", nullptr));
  }

  FlValue* subnets_val = fl_value_lookup_string(args, "hospitalSubnets");
  FlValue* gw_val = fl_value_lookup_string(args, "gateway");
  FlValue* iface_val = fl_value_lookup_string(args, "interfaceName");

  if (!subnets_val || !gw_val || !iface_val) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "invalid_args", "Missing required fields", nullptr));
  }

  const gchar* gw = fl_value_get_string(gw_val);
  const gchar* iface = fl_value_get_string(iface_val);

  GList* added_now = NULL;
  gsize len = fl_value_get_length(subnets_val);

  for (gsize i = 0; i < len; i++) {
    FlValue* entry = fl_value_get_list_value(subnets_val, i);
    if (!entry || fl_value_get_type(entry) != FL_VALUE_TYPE_STRING) continue;

    const gchar* dest = fl_value_get_string(entry);
    g_autofree gchar* cmd = g_strdup_printf(
        "netsh interface ip add route %s %s %s",
        dest, gw, iface);

    int result = system(cmd);
    if (result != 0) {
      // Rollback: remove all previously added routes
      for (GList* l = added_now; l; l = l->next) {
        const gchar* old_dest = (const gchar*)l->data;
        g_autofree gchar* del_cmd = g_strdup_printf(
            "netsh interface ip delete route %s", old_dest);
        system(del_cmd);
      }
      g_list_free_full(added_now, g_free);

      g_autoptr(FlValue) response_map = fl_value_new_map();
      fl_value_append_string(response_map, "success", fl_value_new_bool(FALSE));
      fl_value_append_string(response_map, "message",
          fl_value_new_string("Split tunnel setup failed (rolled back)"));
      return FL_METHOD_RESPONSE(fl_method_success_response_new(response_map));
    }

    added_now = g_list_prepend(added_now, g_strdup(dest));
  }

  // Track routes
  g_mutex_lock(&g_routes_mutex);
  for (GList* l = added_now; l; l = l->next) {
    g_tracked_routes = g_list_prepend(g_tracked_routes, g_strdup((const gchar*)l->data));
  }
  g_mutex_unlock(&g_routes_mutex);

  g_autoptr(FlValue) response_map = fl_value_new_map();
  fl_value_append_string(response_map, "success", fl_value_new_bool(TRUE));
  fl_value_append_string(response_map, "message",
      fl_value_new_string("Split tunnel enabled"));

  g_autoptr(FlValue) affected = fl_value_new_list();
  for (GList* l = added_now; l; l = l->next) {
    fl_value_append(affected, fl_value_new_string((const gchar*)l->data));
  }
  fl_value_append_string(response_map, "affectedRoutes", affected);

  g_list_free_full(added_now, g_free);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(response_map));
}

/* ------------------------------------------------------------------ */
/*  Method call handler                                                 */
/* ------------------------------------------------------------------ */
static void MethodCallHandler(
    FlMethodChannel* channel,
    FlMethodCall* method_call,
    gpointer user_data) {
  (void)channel;
  (void)user_data;

  const gchar* method = fl_method_call_get_name(method_call);
  FlMethodResponse* response = NULL;
  FlValue* args = fl_method_call_get_args(method_call);

  if (strcmp(method, "addRoute") == 0) {
    const gchar *dest = NULL, *gw = NULL, *iface = NULL;
    if (args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* v = fl_value_lookup_string(args, "destinationCidr");
      if (v) dest = fl_value_get_string(v);
      v = fl_value_lookup_string(args, "gateway");
      if (v) gw = fl_value_get_string(v);
      v = fl_value_lookup_string(args, "interfaceName");
      if (v) iface = fl_value_get_string(v);
    }
    response = HandleAddRoute(dest, gw, iface);
  } else if (strcmp(method, "removeRoute") == 0) {
    const gchar* dest = NULL;
    if (args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* v = fl_value_lookup_string(args, "destinationCidr");
      if (v) dest = fl_value_get_string(v);
    }
    response = HandleRemoveRoute(dest);
  } else if (strcmp(method, "enableSplitTunnel") == 0) {
    response = HandleEnableSplitTunnel(args);
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, NULL);
  g_object_unref(response);
}

/* ------------------------------------------------------------------ */
/*  Plugin registration                                                 */
/* ------------------------------------------------------------------ */
void RouteManagerPluginRegisterWithRegistrar(
    FlPluginRegistrar* registrar) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "com.medlinkconnect/route_manager",
      FL_METHOD_CODEC(codec));

  fl_method_channel_set_method_call_handler(
      channel, MethodCallHandler, NULL, NULL);
}
