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

  /// Launches an RDP connection to the given [host].
  ///
  /// Constructs an `rdp://` or `ms-rd-web://` URI and hands it off to
  /// the operating system's registered handler.
  ///
  /// - [host] – Required. IP or FQDN of the target RDP server.
  /// - [port] – Optional. Defaults to `3389`.
  /// - [username] – Optional. Pre-filled in the RDP client.
  /// - [domain] – Optional. Active Directory / NTLM domain.
  /// - [useWebFeed] – When `true`, uses `ms-rd-web://` format.
  /// - [profile] – Connection strategy: `adaptive`, `stable`, or `speed`.
  /// - [measuredLatencyMs] – Optional observed latency used by adaptive mode.
  ///
  /// Returns a human-readable result message (Spanish) for display in
  /// the UI.  Throws on failure so the UI can surface the error.
  Future<String> launchRdp({
    required String host,
    int port = 3389,
    String? username,
    String? domain,
    bool useWebFeed = false,
    String profile = 'adaptive',
    int? measuredLatencyMs,
  });
}
