#include "engine_bridge.h"
#include <stdlib.h>
#include <string.h>

struct RdpEngineHandle {
  RdpEventCallback callback;
  void* user_data;
  int connected;
};

RdpEngineHandle* rdp_engine_create(void) {
  RdpEngineHandle* h = (RdpEngineHandle*)calloc(1, sizeof(RdpEngineHandle));
  if (h) h->connected = 0;
  return h;
}

void rdp_engine_destroy(RdpEngineHandle* handle) {
  if (!handle) return;
  free(handle);
}

int rdp_engine_init(RdpEngineHandle* handle, RdpEventCallback cb, void* user_data) {
  if (!handle) return -1;
  handle->callback = cb;
  handle->user_data = user_data;
  return 0;
}

int rdp_engine_connect(RdpEngineHandle* handle, const char* host, uint16_t port, const char* username, const char* password, const char* domain) {
  (void)host; (void)port; (void)username; (void)password; (void)domain;
  if (!handle) return -1;
  handle->connected = 1;
  if (handle->callback) {
    handle->callback(handle->user_data, RDP_EVENT_CONNECTED, "connected");
  }
  return 0;
}

int rdp_engine_disconnect(RdpEngineHandle* handle) {
  if (!handle) return -1;
  if (handle->connected && handle->callback) {
    handle->callback(handle->user_data, RDP_EVENT_DISCONNECTED, "disconnected");
  }
  handle->connected = 0;
  return 0;
}

int rdp_engine_send_mouse(RdpEngineHandle* handle, int32_t x, int32_t y, uint32_t flags) {
  (void)handle; (void)x; (void)y; (void)flags;
  return 0;
}

int rdp_engine_send_key(RdpEngineHandle* handle, uint32_t scancode, uint32_t flags) {
  (void)handle; (void)scancode; (void)flags;
  return 0;
}

int rdp_engine_send_unicode(RdpEngineHandle* handle, uint32_t codepoint, uint32_t flags) {
  (void)handle; (void)codepoint; (void)flags;
  return 0;
}

int64_t rdp_engine_register_texture(RdpEngineHandle* handle) {
  (void)handle;
  return -1;
}

void rdp_engine_set_surface(RdpEngineHandle* handle, void* surface) {
  (void)handle; (void)surface;
}
