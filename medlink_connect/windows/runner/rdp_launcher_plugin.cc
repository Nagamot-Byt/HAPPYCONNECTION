#include "rdp_launcher_plugin.h"

#include <flutter_windows.h>
#include <windows.h>
#include <shellapi.h>
#include <winreg.h>
#include <string.h>

/* ------------------------------------------------------------------ */
/*  isRdpClientAvailable — check for mstsc.exe                          */
/* ------------------------------------------------------------------ */
static FlMethodResponse* HandleIsRdpClientAvailable() {
  char mstsc_path[MAX_PATH];
  UINT len = GetSystemDirectoryA(mstsc_path, MAX_PATH);
  if (len == 0 || len >= MAX_PATH) {
    return FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_bool(FALSE)));
  }

  strcat_s(mstsc_path, MAX_PATH, "\\mstsc.exe");

  DWORD attribs = GetFileAttributesA(mstsc_path);
  gboolean available = (attribs != INVALID_FILE_ATTRIBUTES &&
                        !(attribs & FILE_ATTRIBUTE_DIRECTORY));

  return FL_METHOD_RESPONSE(fl_method_success_response_new(
      fl_value_new_bool(available)));
}

/* ------------------------------------------------------------------ */
/*  getDetectedRdpClient — return "Microsoft Remote Desktop"             */
/* ------------------------------------------------------------------ */
static FlMethodResponse* HandleGetDetectedRdpClient() {
  DWORD attribs = GetFileAttributesA("C:\\Windows\\System32\\mstsc.exe");
  if (attribs != INVALID_FILE_ATTRIBUTES &&
      !(attribs & FILE_ATTRIBUTE_DIRECTORY)) {
    return FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_string("Microsoft Remote Desktop")));
  }

  return FL_METHOD_RESPONSE(fl_method_success_response_new(
      fl_value_new_string(NULL)));
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

  if (strcmp(method, "isRdpClientAvailable") == 0) {
    response = HandleIsRdpClientAvailable();
  } else if (strcmp(method, "getDetectedRdpClient") == 0) {
    response = HandleGetDetectedRdpClient();
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, NULL);
  g_object_unref(response);
}

/* ------------------------------------------------------------------ */
/*  Plugin registration                                                 */
/* ------------------------------------------------------------------ */
void RdpLauncherPluginRegisterWithRegistrar(
    FlPluginRegistrar* registrar) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "com.medlinkconnect/rdp_launcher",
      FL_METHOD_CODEC(codec));

  fl_method_channel_set_method_call_handler(
      channel, MethodCallHandler, NULL, NULL);
}
