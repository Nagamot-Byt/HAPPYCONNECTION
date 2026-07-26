#include "network_diagnostics_plugin.h"

#include <flutter_windows.h>
#include <winsock2.h>
#include <iphlpapi.h>
#include <icmpapi.h>
#include <stdio.h>
#pragma comment(lib, "winsock2.lib")
#pragma comment(lib, "iphlpapi.lib")
#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "winmm.lib")

/* ------------------------------------------------------------------ */
/*  flushDns — Windows DNS cache flush                                 */
/* ------------------------------------------------------------------ */
static FlMethodResponse* HandleFlushDns() {
  HANDLE hFlushToken = NULL;
  DWORD Status = DnsFlushResolverCache();
  
  if (Status == NO_ERROR) {
    return FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_bool(TRUE)));
  }
  
  return FL_METHOD_RESPONSE(fl_method_success_response_new(
      fl_value_new_bool(FALSE)));
}

/* ------------------------------------------------------------------ */
/*  clearNetworkCaches — Windows ARP cache flush                       */
/* ------------------------------------------------------------------ */
static FlMethodResponse* HandleClearNetworkCaches() {
  DWORD Status = FlushIpNetTable(AF_UNSPEC);
  
  if (Status == NO_ERROR) {
    return FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_bool(TRUE)));
  }
  
  return FL_METHOD_RESPONSE(fl_method_success_response_new(
      fl_value_new_bool(FALSE)));
}

/* ------------------------------------------------------------------ */
/*  ping — Windows ICMP echo request                                   */
/* ------------------------------------------------------------------ */
static FlMethodResponse* HandlePing(const char* host) {
  if (!host || !host[0]) {
    return FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_int(-1)));
  }

  // Resolve hostname to IP
  struct addrinfo hints = {}, * results = NULL;
  hints.ai_family = AF_INET;
  hints.ai_socktype = SOCK_STREAM;
  
  if (getaddrinfo(host, NULL, &hints, &results) != 0) {
    return FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_int(-1)));
  }

  struct sockaddr_in* addr_in = (struct sockaddr_in*)results->ai_addr;
  IPAddr ipaddr = addr_in->sin_addr.S_un.S_addr;
  freeaddrinfo(results);

  // Create ICMP handle
  HANDLE hIcmpFile = IcmpSendEcho(INVALID_HANDLE_VALUE, ipaddr, NULL, 0, NULL);
  if (hIcmpFile == INVALID_HANDLE_VALUE) {
    return FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_int(-1)));
  }

  // Wait for reply
  DWORD dwRetVal = NO_ERROR;
  char SendData[32] = "Data Buffer";
  DWORD ReplySize = ICMP_ECHO_REPLY_SIZE + sizeof(SendData);
  void* ReplyBuffer = malloc(ReplySize);
  if (ReplyBuffer == NULL) {
    return FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_int(-1)));
  }

  dwRetVal = IcmpSendEcho(INVALID_HANDLE_VALUE, ipaddr, SendData, sizeof(SendData), NULL);
  if (dwRetVal == 0) {
    free(ReplyBuffer);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_int(-1)));
  }

  // Parse reply
  PICMP_ECHO_REPLY pEchoReply = (PICMP_ECHO_REPLY)ReplyBuffer;
  struct IpAddr ReplySource = pEchoReply->Address;
  unsigned long ipaddr_replied = pEchoReply->Address;

  long avg_ms = -1;
  if (pEchoReply->Status == IP_SUCCESS) {
    avg_ms = pEchoReply->RoundTripTime;
  }

  IcmpSendEcho(INVALID_HANDLE_VALUE, 0, NULL, 0, NULL);
  free(ReplyBuffer);

  return FL_METHOD_RESPONSE(fl_method_success_response_new(
      fl_value_new_int((int32_t)avg_ms)));
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

  if (strcmp(method, "flushDns") == 0) {
    response = HandleFlushDns();
  } else if (strcmp(method, "clearNetworkCaches") == 0) {
    response = HandleClearNetworkCaches();
  } else if (strcmp(method, "ping") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    const gchar* host = NULL;
    if (args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* host_val = fl_value_lookup_string(args, "host");
      if (host_val && fl_value_get_type(host_val) == FL_VALUE_TYPE_STRING) {
        host = fl_value_get_string(host_val);
      }
    }
    response = HandlePing(host);
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, NULL);
  g_object_unref(response);
}

/* ------------------------------------------------------------------ */
/*  Plugin registration                                                 */
/* ------------------------------------------------------------------ */
void NetworkDiagnosticsPluginRegisterWithRegistrar(
    FlPluginRegistrar* registrar) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "com.medlinkconnect/network_diagnostics",
      FL_METHOD_CODEC(codec));

  fl_method_channel_set_method_call_handler(
      channel, MethodCallHandler, NULL, NULL);
}
