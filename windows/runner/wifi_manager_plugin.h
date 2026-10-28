#ifndef RUNNER_WIFI_MANAGER_PLUGIN_H_
#define RUNNER_WIFI_MANAGER_PLUGIN_H_

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <flutter/flutter_engine.h>

// Registers the com.medlinkconnect/wifi_manager method channel.
void WifiManagerPluginRegisterWithRegistrar(
    flutter::FlutterEngine* engine);

#endif  // RUNNER_WIFI_MANAGER_PLUGIN_H_
