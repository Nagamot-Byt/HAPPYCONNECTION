cmake_minimum_required(VERSION 3.22.1)
project("medlink_rdp_bridge")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_C_STANDARD 11)

include_directories(
    ${CMAKE_SOURCE_DIR}/../../../../../native/bridge
    ${CMAKE_SOURCE_DIR}/../../../../../native/freerdp/include
    ${CMAKE_SOURCE_DIR}/../../../../../native/freerdp/winpr/include
)

add_library(
    medlink_rdp_bridge
    SHARED
    jni_bridge.cpp
    ${CMAKE_SOURCE_DIR}/../../../../../native/bridge/engine_bridge.c
)

find_library(log-lib log)
target_link_libraries(
    medlink_rdp_bridge
    ${log-lib}
    android
)
