#ifndef NETWORK_DIAGNOSTICS_PLUGIN_H_
#define NETWORK_DIAGNOSTICS_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

G_DECLARE_FINAL_TYPE(NetworkDiagnosticsPlugin,
                     network_diagnostics_plugin,
                     NETWORK_DIAGNOSTICS,
                     PLUGIN,
                     GObject)

/// Register the network diagnostics plugin with the given [registrar].
void network_diagnostics_plugin_register_with_registrar(
    FlPluginRegistrar* registrar);

G_END_DECLS

#endif  // NETWORK_DIAGNOSTICS_PLUGIN_H_
