#ifndef RUNNER_ROUTE_MANAGER_PLUGIN_H_
#define RUNNER_ROUTE_MANAGER_PLUGIN_H_

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <flutter/flutter_engine.h>

// Registers the com.medlinkconnect/route_manager method channel.
void RouteManagerPluginRegisterWithRegistrar(
    flutter::FlutterEngine* engine);

#endif  // RUNNER_ROUTE_MANAGER_PLUGIN_H_
