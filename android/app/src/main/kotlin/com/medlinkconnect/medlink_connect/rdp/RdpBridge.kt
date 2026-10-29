package com.medlinkconnect.medlink_connect.rdp

/**
 * JNI bridge for the native FreeRDP engine.
 *
 * The native library exposes these symbols as instance methods on this class;
 * keep the package and method names in sync with `jni_bridge.cpp`.
 */
class RdpBridge {
    companion object {
        init {
            System.loadLibrary("medlink_rdp_bridge")
        }
    }

    external fun nativeCreate(): Long

    external fun nativeDestroy(handle: Long)

    fun create(): Long = nativeCreate()

    fun destroy(handle: Long) = nativeDestroy(handle)
}
