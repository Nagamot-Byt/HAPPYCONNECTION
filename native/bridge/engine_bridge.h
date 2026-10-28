#ifndef MEDLINK_ENGINE_BRIDGE_H_
#define MEDLINK_ENGINE_BRIDGE_H_

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct RdpEngineHandle RdpEngineHandle;

typedef enum {
  RDP_EVENT_CONNECTED = 0,
  RDP_EVENT_DISCONNECTED = 1,
  RDP_EVENT_ERROR = 2,
  RDP_EVENT_FRAME_READY = 3,
  RDP_EVENT_RESIZED = 4
} RdpEngineEventType;

typedef void (*RdpEventCallback)(void* user_data, RdpEngineEventType type, const char* message);

RdpEngineHandle* rdp_engine_create(void);
void rdp_engine_destroy(RdpEngineHandle* handle);

int rdp_engine_init(RdpEngineHandle* handle, RdpEventCallback cb, void* user_data);
int rdp_engine_connect(RdpEngineHandle* handle, const char* host, uint16_t port, const char* username, const char* password, const char* domain);
int rdp_engine_disconnect(RdpEngineHandle* handle);

int rdp_engine_send_mouse(RdpEngineHandle* handle, int32_t x, int32_t y, uint32_t flags);
int rdp_engine_send_key(RdpEngineHandle* handle, uint32_t scancode, uint32_t flags);
int rdp_engine_send_unicode(RdpEngineHandle* handle, uint32_t codepoint, uint32_t flags);

int64_t rdp_engine_register_texture(RdpEngineHandle* handle);
void rdp_engine_set_surface(RdpEngineHandle* handle, void* surface);

#ifdef __cplusplus
}
#endif

#endif
