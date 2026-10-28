#ifndef NETWORK_DIAGNOSTICS_PLUGIN_H_
#define NETWORK_DIAGNOSTICS_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

/**
 * Registers the network diagnostics plugin with the given Flutter registrar.
 *
 * The plugin handles the `com.medlinkconnect/network_diagnostics` method
 * channel and provides the following methods:
 *
 * - flushDns           : Flush DNS resolver cache
 * - clearNetworkCaches : Clear ARP and other neighbour caches
 * - ping               : ICMP echo probe, returns average RTT in ms
 */
void network_diagnostics_plugin_register_with_registrar(
    FlPluginRegistrar* registrar);

G_END_DECLS

#endif  // NETWORK_DIAGNOSTICS_PLUGIN_H_
