#ifndef RDP_LAUNCHER_PLUGIN_H_
#define RDP_LAUNCHER_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

/**
 * Registers the RDP launcher plugin with the given Flutter registrar.
 *
 * The plugin handles the `com.medlinkconnect/rdp_launcher` method channel
 * and provides the following methods:
 *
 * - preLaunch            : Verify xdg-open + rdp:// scheme handler
 * - isRdpClientAvailable : Check for Remmina, FreeRDP, or mstsc
 */
void rdp_launcher_plugin_register_with_registrar(
    FlPluginRegistrar* registrar);

G_END_DECLS

#endif  // RDP_LAUNCHER_PLUGIN_H_
