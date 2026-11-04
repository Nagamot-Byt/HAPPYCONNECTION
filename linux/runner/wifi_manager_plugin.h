#ifndef WIFI_MANAGER_PLUGIN_H_
#define WIFI_MANAGER_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

/**
 * Registers the Wi-Fi manager plugin with the given Flutter registrar.
 *
 * The plugin handles the `com.medlinkconnect/wifi_manager` method channel and
 * uses NetworkManager's `nmcli` client so it works across Linux desktops:
 *
 * - scanNetworks   : List visible Wi-Fi SSIDs
 * - connect        : Connect to an SSID, optionally creating a WPA profile
 * - getCurrentInfo : Report the active SSID, interface and IPv4 gateway
 */
void wifi_manager_plugin_register_with_registrar(
    FlPluginRegistrar* registrar);

G_END_DECLS

#endif  // WIFI_MANAGER_PLUGIN_H_
