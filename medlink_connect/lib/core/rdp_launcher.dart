/// Abstract interface for launching an RDP session via deep linking.
///
/// We never embed an RDP viewer — we always delegate to Microsoft's
/// official Remote Desktop client (or a compatible third-party client)
/// using the `rdp://` or `ms-rd-web://` URI scheme.
abstract class RdpLauncher {
  /// Launch the Microsoft Remote Desktop client (or equivalent) with the
  /// given connection parameters.
  ///
  /// [address] — target hostname or IP
  /// [port] — RDP port (default 3389)
  /// [username] — optional pre-filled username
  /// [fullAddress] — full `rdp://fullAddress` URI to pass verbatim
  ///
  /// Returns `true` if a compatible client was found and launched.
  Future<bool> launchRdp({
    String? address,
    int port = 3389,
    String? username,
    String? fullAddress,
  });

  /// Check whether an RDP client is installed on this device.
  Future<bool> isRdpClientAvailable();
}
