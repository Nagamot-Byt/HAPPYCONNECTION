/// Abstract interface for launching RDP connections.
///
/// Platform implementations use method channels
/// (`com.medlinkconnect/rdp_launcher`) to invoke native code.
abstract class RdpLauncher {
  /// Prepares the environment for an RDP launch.
  ///
  /// On Linux this verifies that `xdg-open` is available and that an
  /// `rdp://` (or `ms-rd-web://`) scheme handler is registered.
  /// Returns `true` when the pre-flight checks pass.
  Future<bool> preLaunch();

  /// Returns `true` when an RDP client (Remmina, FreeRDP, or Microsoft
  /// Remote Desktop) is available on the system.
  Future<bool> isRdpClientAvailable();
}
