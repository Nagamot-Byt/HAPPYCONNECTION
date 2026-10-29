#include <jni.h>
#include "../../../../../native/bridge/engine_bridge.h"

extern "C" JNIEXPORT jlong JNICALL
Java_com_medlinkconnect_medlink_1connect_rdp_RdpBridge_nativeCreate(JNIEnv*, jobject) {
    return (jlong)(intptr_t)rdp_engine_create();
}

extern "C" JNIEXPORT void JNICALL
Java_com_medlinkconnect_medlink_1connect_rdp_RdpBridge_nativeDestroy(JNIEnv*, jobject, jlong handle) {
    rdp_engine_destroy((RdpEngineHandle*)(intptr_t)handle);
}
