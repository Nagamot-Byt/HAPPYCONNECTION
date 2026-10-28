/// Base exception for all MedLink Connect specific errors.
abstract class MedLinkException implements Exception {
  final String message;
  const MedLinkException(this.message);

  @override
  String toString() => message;
}

/// Thrown when there is an issue with the Wi-Fi connection.
class WifiConnectionException extends MedLinkException {
  const WifiConnectionException(super.message);
}

/// Thrown when there is an issue with network routes or split tunneling.
class RouteConfigurationException extends MedLinkException {
  const RouteConfigurationException(super.message);
}

/// Thrown when the RDP server cannot be reached on the specified TCP port.
class RdpTimeoutException extends MedLinkException {
  const RdpTimeoutException(super.message);
}

/// Thrown when the RDP client fails to launch.
class RdpLaunchException extends MedLinkException {
  const RdpLaunchException(super.message);
}

/// Thrown when elevated privileges are required but not present.
class PrivilegeRequiredException extends MedLinkException {
  const PrivilegeRequiredException(super.message);
}

/// Thrown for general network diagnostic failures.
class NetworkDiagnosticException extends MedLinkException {
  const NetworkDiagnosticException(super.message);
}
