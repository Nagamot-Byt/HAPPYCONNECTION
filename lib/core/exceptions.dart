/// Typed error categories used by the UI to choose guidance without relying
/// on message text.
enum MedLinkErrorType {
  permission,
  wifi,
  route,
  rdp,
  network,
  validation,
  unknown,
}

/// Base exception for all MedLink Connect specific errors.
abstract class MedLinkException implements Exception {
  final String message;
  final MedLinkErrorType type;

  const MedLinkException(
    this.message, {
    this.type = MedLinkErrorType.unknown,
  });

  @override
  String toString() => message;
}

/// Thrown when there is an issue with the Wi-Fi connection.
class WifiConnectionException extends MedLinkException {
  const WifiConnectionException(super.message)
      : super(type: MedLinkErrorType.wifi);
}

/// Thrown when there is an issue with network routes or split tunneling.
class RouteConfigurationException extends MedLinkException {
  const RouteConfigurationException(super.message)
      : super(type: MedLinkErrorType.route);
}

/// Thrown when the RDP server cannot be reached on the specified TCP port.
class RdpTimeoutException extends MedLinkException {
  const RdpTimeoutException(super.message) : super(type: MedLinkErrorType.rdp);
}

/// Thrown when the RDP client fails to launch.
class RdpLaunchException extends MedLinkException {
  const RdpLaunchException(super.message) : super(type: MedLinkErrorType.rdp);
}

/// Thrown when elevated privileges are required but not present.
class PrivilegeRequiredException extends MedLinkException {
  const PrivilegeRequiredException(super.message)
      : super(type: MedLinkErrorType.permission);
}

/// Thrown for general network diagnostic failures.
class NetworkDiagnosticException extends MedLinkException {
  const NetworkDiagnosticException(super.message)
      : super(type: MedLinkErrorType.network);
}
