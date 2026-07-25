/// Abstract interface for managing static IP routes and split-tunneling.
///
/// Platform implementations use method channels
/// (`com.medlinkconnect/route_manager`) to invoke native code.
abstract class RouteManager {
  /// Adds a static route: `ip route add <destinationCidr> via <gateway> dev <interfaceName>`.
  Future<String> addRoute({
    required String destinationCidr,
    required String gateway,
    required String interfaceName,
  });

  /// Removes a previously added route.
  Future<String> removeRoute({required String destinationCidr});

  /// Enables split-tunneling by adding one route for every subnet in
  /// [hospitalSubnets]. If any route fails, all previously added routes
  /// are rolled back.
  Future<String> enableSplitTunnel({
    required List<String> hospitalSubnets,
    required String gateway,
    required String interfaceName,
  });

  /// Disables split-tunneling by removing every route that was added
  /// by [enableSplitTunnel].
  Future<String> disableSplitTunnel();

  /// Returns the raw output of `ip route show`.
  Future<String> getRoutes();

  /// Returns a list of available network interface names.
  Future<List<String>> listInterfaces();
}
