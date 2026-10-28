#ifndef ROUTE_MANAGER_PLUGIN_H_
#define ROUTE_MANAGER_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

/**
 * Registers the route manager plugin with the given Flutter registrar.
 *
 * The plugin handles the `com.medlinkconnect/route_manager` method channel
 * and provides the following methods:
 *
 * - addRoute           : ip route add <cidr> via <gw> dev <iface>
 * - removeRoute        : ip route del <cidr>
 * - enableSplitTunnel  : Add all hospital subnets; rollback on failure
 * - disableSplitTunnel : Remove all tracked routes
 * - getRoutes          : Return raw `ip route show` output
 * - listInterfaces     : Return parsed interface names
 */
void route_manager_plugin_register_with_registrar(
    FlPluginRegistrar* registrar);

G_END_DECLS

#endif  // ROUTE_MANAGER_PLUGIN_H_
