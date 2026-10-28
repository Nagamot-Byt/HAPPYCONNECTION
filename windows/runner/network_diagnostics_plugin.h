#ifndef RUNNER_NETWORK_DIAGNOSTICS_PLUGIN_H_
#define RUNNER_NETWORK_DIAGNOSTICS_PLUGIN_H_

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <flutter/flutter_engine.h>

// Registers the com.medlinkconnect/network_diagnostics method channel
// handler with the given Flutter engine.
void NetworkDiagnosticsPluginRegisterWithRegistrar(
    flutter::FlutterEngine* engine);

#endif  // RUNNER_NETWORK_DIAGNOSTICS_PLUGIN_H_
