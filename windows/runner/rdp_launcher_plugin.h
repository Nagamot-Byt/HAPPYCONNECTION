#ifndef RUNNER_RDP_LAUNCHER_PLUGIN_H_
#define RUNNER_RDP_LAUNCHER_PLUGIN_H_

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <flutter/flutter_engine.h>

// Registers the com.medlinkconnect/rdp_launcher method channel.
void RdpLauncherPluginRegisterWithRegistrar(
    flutter::FlutterEngine* engine);

#endif  // RUNNER_RDP_LAUNCHER_PLUGIN_H_
